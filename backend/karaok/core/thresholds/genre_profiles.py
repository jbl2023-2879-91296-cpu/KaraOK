"""Immutable, validated genre-specific audio target profiles."""

from __future__ import annotations

import json
import math
import re
from dataclasses import dataclass
from datetime import datetime
from functools import lru_cache
from pathlib import Path
from types import MappingProxyType
from typing import Any, Literal, Mapping

from .artifact_integrity import canonical_artifact_checksum


SUPPORTED_METRICS = ("loudness", "bass", "treble", "sharpness", "flatness")
METRIC_UNITS = {
    "loudness": "LUFS",
    "bass": "percent",
    "treble": "percent",
    "sharpness": "normalized_score",
    "flatness": "ratio",
}
INSTRUMENTAL_STATUSES = frozenset({"confirmed_instrumental", "unverified"})
GENERATOR_VERSION = "1.0.0"
SELECTION_FILTER_KEYS = frozenset({"individual_license", "measurement_source"})
MEASUREMENT_SOURCE = "KaraOK audio_engine.analyze_audio"
InstrumentalStatus = Literal["confirmed_instrumental", "unverified"]
ARTIFACT_KEYS = frozenset(
    {
        "schema_version",
        "profile_version",
        "generated_at",
        "generator_version",
        "sources",
        "artifact_checksum",
        "genres",
    }
)
PROFILE_KEYS = frozenset({"sample_count", "corpus_status", "metrics"})
TARGET_KEYS = frozenset({"lower", "preferred", "upper", "robust_scale", "unit"})
SOURCE_KEYS = frozenset(
    {
        "source",
        "release",
        "license",
        "citation_url",
        "selection_filters",
        "compatible_feature_notes",
        "calculation_method",
        "recordings",
    }
)
RECORDING_KEYS = frozenset({"recording_id", "genre", "instrumental_status"})
GENRE_ALIASES = {
    "rock": "rock",
    "pop": "pop",
    "ballad": "ballad",
    "hiphop": "hip-hop",
    "hip-hop": "hip-hop",
    "hip hop": "hip-hop",
    "classic": "classical",
    "classical": "classical",
    "r&b": "r&b",
    "rnb": "r&b",
    "soul-rnb": "r&b",
    "general": "general",
    "other": "general",
    "general/other": "general",
}
DEFAULT_GENRE_PROFILE_PATH = (Path(__file__).resolve().parents[3] / "audio_thresholds").joinpath("genre_audio_profiles.json")


@dataclass(frozen=True)
class MetricTarget:
    lower: float
    preferred: float
    upper: float
    robust_scale: float
    unit: str


@dataclass(frozen=True)
class GenreProfile:
    key: str
    sample_count: int
    corpus_status: InstrumentalStatus
    metrics: Mapping[str, MetricTarget]


@dataclass(frozen=True)
class GenreProfileArtifact:
    schema_version: int
    profile_version: str
    generated_at: str
    generator_version: str
    sources: Mapping[str, Any]
    artifact_checksum: str
    genres: Mapping[str, GenreProfile]

    def profile_for(self, genre: str) -> GenreProfile:
        """Return the profile corresponding to a supported user genre label."""

        key = normalize_genre(genre)
        try:
            return self.genres[key]
        except KeyError as error:
            raise ValueError(f"Genre profile is not available for {key!r}") from error


def normalize_genre(value: str) -> str:
    """Return the canonical key for a supported genre label."""

    if not isinstance(value, str):
        raise ValueError("Genre label must be a string")
    normalized = value.strip().lower()
    try:
        return GENRE_ALIASES[normalized]
    except KeyError as error:
        raise ValueError(f"Unsupported genre label: {value!r}") from error


def _exact_mapping(value: Any, keys: frozenset[str] | set[str], field: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise ValueError(f"{field} must be an object")
    actual = set(value)
    expected = set(keys)
    if actual != expected:
        raise ValueError(
            f"{field} fields do not match the genre-profile schema; "
            f"missing={sorted(expected - actual)}, unknown={sorted(actual - expected)}"
        )
    return value


def _strict_finite(value: Any, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{field} must be a finite number")
    number = float(value)
    if not math.isfinite(number):
        raise ValueError(f"{field} must be a finite number")
    return number


def _metric_target(data: Mapping[str, Any], metric: str) -> MetricTarget:
    data = _exact_mapping(data, TARGET_KEYS, f"Genre metric {metric!r}")
    unit = data["unit"]
    if not isinstance(unit, str) or unit != METRIC_UNITS[metric]:
        raise ValueError(
            f"Genre metric {metric!r} unit must be {METRIC_UNITS[metric]!r}"
        )
    target = MetricTarget(
        lower=_strict_finite(data["lower"], f"Genre metric {metric!r}.lower"),
        preferred=_strict_finite(
            data["preferred"], f"Genre metric {metric!r}.preferred"
        ),
        upper=_strict_finite(data["upper"], f"Genre metric {metric!r}.upper"),
        robust_scale=_strict_finite(
            data["robust_scale"], f"Genre metric {metric!r}.robust_scale"
        ),
        unit=unit,
    )
    if not target.lower < target.preferred < target.upper:
        raise ValueError("Genre metric values must satisfy lower < preferred < upper")
    if target.robust_scale <= 0:
        raise ValueError("Genre metric robust_scale must be positive")
    return target


def _freeze(value: Any) -> Any:
    if isinstance(value, Mapping):
        return MappingProxyType({key: _freeze(item) for key, item in value.items()})
    if isinstance(value, list):
        return tuple(_freeze(item) for item in value)
    return value


def _required_string(data: Mapping[str, Any], name: str) -> str:
    value = data.get(name)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"Genre profile artifact requires non-empty {name!r}")
    return value


def _source_entries(sources: Any) -> tuple[Mapping[str, Any], ...]:
    if isinstance(sources, Mapping):
        return (sources,)
    if isinstance(sources, list) and sources and all(
        isinstance(source, Mapping) for source in sources
    ):
        return tuple(sources)
    raise ValueError("Genre profile artifact requires source metadata objects")


def _validated_source_recordings(
    sources: Any,
    profiles: Mapping[str, GenreProfile],
) -> None:
    """Require auditable licensed recordings for every enabled genre profile."""

    statuses: dict[str, list[str]] = {key: [] for key in profiles}
    recording_ids: set[str] = set()
    for source in _source_entries(sources):
        source = _exact_mapping(source, SOURCE_KEYS, "Genre profile source")
        _required_string(source, "source")
        _required_string(source, "release")
        _required_string(source, "license")
        citation_url = _required_string(source, "citation_url")
        if re.fullmatch(r"https?://\S+", citation_url) is None:
            raise ValueError("Genre profile source citation_url must be an HTTP(S) URL")
        filters = _exact_mapping(
            source.get("selection_filters"),
            SELECTION_FILTER_KEYS,
            "Genre profile source selection_filters",
        )
        if _required_string(filters, "individual_license") != source["license"]:
            raise ValueError(
                "Genre profile source selection_filters individual_license "
                "must match source license"
            )
        if _required_string(filters, "measurement_source") != MEASUREMENT_SOURCE:
            raise ValueError(
                "Genre profile source selection_filters measurement_source "
                "does not match the derivation source"
            )
        _required_string(source, "compatible_feature_notes")
        _required_string(source, "calculation_method")
        recordings = source.get("recordings")
        if not isinstance(recordings, list) or not recordings:
            raise ValueError("Genre profile source requires non-empty recordings")
        for recording in recordings:
            recording = _exact_mapping(
                recording, RECORDING_KEYS, "Genre profile source recording"
            )
            recording_id = _required_string(recording, "recording_id")
            if recording_id in recording_ids:
                raise ValueError(f"Genre profile sources duplicate recording_id {recording_id!r}")
            recording_ids.add(recording_id)
            raw_genre = _required_string(recording, "genre")
            genre = normalize_genre(raw_genre)
            if raw_genre != genre:
                raise ValueError(
                    "Genre profile source recording genre must use its canonical key"
                )
            if genre not in statuses:
                raise ValueError(f"Licensed recording cohort has no enabled profile for {genre!r}")
            instrumental_status = _required_string(recording, "instrumental_status")
            if instrumental_status not in INSTRUMENTAL_STATUSES:
                raise ValueError(
                    "Genre profile source recording instrumental_status must be "
                    "'confirmed_instrumental' or 'unverified'"
                )
            statuses[genre].append(instrumental_status)

    for key, profile in profiles.items():
        recording_statuses = statuses[key]
        if len(recording_statuses) != profile.sample_count:
            raise ValueError(
                f"Genre profile {key!r} licensed recording cohort has "
                f"{len(recording_statuses)} recordings; "
                f"expected {profile.sample_count}"
            )
        expected_status = (
            "confirmed_instrumental"
            if all(status == "confirmed_instrumental" for status in recording_statuses)
            else "unverified"
        )
        if profile.corpus_status != expected_status:
            raise ValueError(
                f"Genre profile {key!r} corpus_status does not match recording evidence"
            )


def parse_genre_profile_artifact(data: Mapping[str, Any]) -> GenreProfileArtifact:
    """Validate and parse a JSON-compatible genre profile artifact."""

    data = _exact_mapping(data, ARTIFACT_KEYS, "Genre profile artifact")
    if (
        isinstance(data.get("schema_version"), bool)
        or not isinstance(data.get("schema_version"), int)
        or data["schema_version"] != 1
    ):
        raise ValueError("Unsupported genre profile schema_version; expected 1")

    profile_version = _required_string(data, "profile_version")
    generated_at = _required_string(data, "generated_at")
    generator_version = _required_string(data, "generator_version")
    try:
        parsed_generated_at = datetime.strptime(generated_at, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as error:
        raise ValueError(
            "Genre profile generated_at must be a canonical UTC timestamp"
        ) from error
    if parsed_generated_at.strftime("%Y-%m-%dT%H:%M:%SZ") != generated_at:
        raise ValueError("Genre profile generated_at must be a canonical UTC timestamp")
    if generator_version != GENERATOR_VERSION:
        raise ValueError("Unsupported genre profile generator_version")
    sources = data.get("sources")

    genres_data = data.get("genres")
    if not isinstance(genres_data, Mapping) or not genres_data:
        raise ValueError("Genre profile artifact requires a non-empty genres object")

    normalized_genre_keys = [normalize_genre(raw_key) for raw_key in genres_data]
    if len(set(normalized_genre_keys)) != len(normalized_genre_keys):
        raise ValueError("Genre profile artifact has duplicate normalized genre keys")

    profiles: dict[str, GenreProfile] = {}
    for raw_key, raw_profile in genres_data.items():
        key = normalize_genre(raw_key)
        if raw_key != key:
            raise ValueError(f"Genre profile key {raw_key!r} is not canonical")
        if not isinstance(raw_profile, Mapping):
            raise ValueError(f"Genre profile {key!r} must be an object")
        raw_profile = _exact_mapping(
            raw_profile, PROFILE_KEYS, f"Genre profile {key!r}"
        )
        sample_count = raw_profile.get("sample_count")
        if isinstance(sample_count, bool) or not isinstance(sample_count, int) or sample_count < 5:
            raise ValueError(f"Genre profile {key!r} sample_count must be at least 5")
        corpus_status = raw_profile.get("corpus_status")
        if corpus_status not in INSTRUMENTAL_STATUSES:
            raise ValueError(
                f"Genre profile {key!r} corpus_status must be "
                "'confirmed_instrumental' or 'unverified'"
            )
        raw_metrics = raw_profile.get("metrics")
        if not isinstance(raw_metrics, Mapping) or set(raw_metrics) != set(SUPPORTED_METRICS):
            raise ValueError(f"Genre profile {key!r} must contain exactly the supported metrics")
        metrics: dict[str, MetricTarget] = {}
        for metric in SUPPORTED_METRICS:
            raw_target = raw_metrics[metric]
            if not isinstance(raw_target, Mapping):
                raise ValueError(f"Genre metric {metric!r} must be an object")
            try:
                metrics[metric] = _metric_target(raw_target, metric)
            except (KeyError, TypeError, ValueError) as error:
                if isinstance(error, ValueError):
                    raise
                raise ValueError(f"Genre metric {metric!r} is incomplete") from error
        profiles[key] = GenreProfile(
            key,
            sample_count,
            corpus_status,
            MappingProxyType(metrics),
        )

    _validated_source_recordings(sources, profiles)

    checksum = _required_string(data, "artifact_checksum")
    if re.fullmatch(r"[0-9a-f]{64}", checksum) is None:
        raise ValueError("Genre profile artifact requires a SHA-256 artifact_checksum")
    expected_checksum = canonical_artifact_checksum(data)
    if checksum != expected_checksum:
        raise ValueError("Genre profile artifact checksum does not match canonical content")

    return GenreProfileArtifact(
        schema_version=1,
        profile_version=profile_version,
        generated_at=generated_at,
        generator_version=generator_version,
        sources=_freeze(sources),
        artifact_checksum=checksum,
        genres=MappingProxyType(profiles),
    )


@lru_cache(maxsize=None)
def _load_genre_profiles_cached(path: str) -> GenreProfileArtifact:
    profile_path = Path(path)
    try:
        data = json.loads(profile_path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ValueError(f"Genre profile file does not exist: {profile_path}") from error
    except json.JSONDecodeError as error:
        raise ValueError(f"Genre profile file is not valid JSON: {error}") from error
    return parse_genre_profile_artifact(data)


def clear_genre_profile_cache() -> None:
    """Clear cached artifacts for isolated tests or explicit runtime reloads."""

    _load_genre_profiles_cached.cache_clear()


def load_genre_profiles(
    path: str | Path = DEFAULT_GENRE_PROFILE_PATH,
) -> GenreProfileArtifact:
    """Load and validate a genre profile artifact from JSON."""

    return _load_genre_profiles_cached(str(Path(path).resolve()))
