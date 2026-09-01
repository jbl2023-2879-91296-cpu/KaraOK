"""Immutable, validated genre-specific audio target profiles."""

from __future__ import annotations

import hashlib
import json
import math
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from types import MappingProxyType
from typing import Any, Mapping


SUPPORTED_METRICS = ("loudness", "bass", "treble", "sharpness", "flatness")
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
DEFAULT_GENRE_PROFILE_PATH = Path(__file__).with_name("genre_audio_profiles.json")


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


def _metric_target(data: Mapping[str, Any]) -> MetricTarget:
    target = MetricTarget(
        lower=float(data["lower"]),
        preferred=float(data["preferred"]),
        upper=float(data["upper"]),
        robust_scale=float(data["robust_scale"]),
        unit=str(data["unit"]),
    )
    values = (target.lower, target.preferred, target.upper, target.robust_scale)
    if not all(math.isfinite(value) for value in values):
        raise ValueError("Genre metric values must be finite")
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


def _canonical_checksum(data: Mapping[str, Any]) -> str:
    canonical = dict(data)
    canonical.pop("artifact_checksum", None)
    encoded = json.dumps(canonical, sort_keys=True, separators=(",", ":"), allow_nan=False)
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


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

    counts = {key: 0 for key in profiles}
    recording_ids: set[str] = set()
    for source in _source_entries(sources):
        _required_string(source, "source")
        if not (
            isinstance(source.get("release"), str)
            and source["release"].strip()
            or isinstance(source.get("checksum"), str)
            and source["checksum"].strip()
        ):
            raise ValueError("Genre profile source requires a release or checksum")
        _required_string(source, "license")
        _required_string(source, "citation_url")
        filters = source.get("selection_filters")
        if not isinstance(filters, Mapping) or not filters:
            raise ValueError("Genre profile source requires selection_filters")
        _required_string(source, "compatible_feature_notes")
        _required_string(source, "calculation_method")
        recordings = source.get("recordings")
        if not isinstance(recordings, list) or not recordings:
            raise ValueError("Genre profile source requires non-empty recordings")
        for recording in recordings:
            if not isinstance(recording, Mapping):
                raise ValueError("Genre profile source recording must be an object")
            recording_id = _required_string(recording, "recording_id")
            if recording_id in recording_ids:
                raise ValueError(f"Genre profile sources duplicate recording_id {recording_id!r}")
            recording_ids.add(recording_id)
            genre = normalize_genre(_required_string(recording, "genre"))
            if genre not in counts:
                raise ValueError(f"Licensed recording cohort has no enabled profile for {genre!r}")
            counts[genre] += 1

    for key, profile in profiles.items():
        if counts[key] != profile.sample_count:
            raise ValueError(
                f"Genre profile {key!r} licensed recording cohort has {counts[key]} recordings; "
                f"expected {profile.sample_count}"
            )


def parse_genre_profile_artifact(data: Mapping[str, Any]) -> GenreProfileArtifact:
    """Validate and parse a JSON-compatible genre profile artifact."""

    if not isinstance(data, Mapping):
        raise ValueError("Genre profile artifact must be an object")
    if data.get("schema_version") != 1:
        raise ValueError("Unsupported genre profile schema_version; expected 1")

    profile_version = _required_string(data, "profile_version")
    generated_at = _required_string(data, "generated_at")
    generator_version = _required_string(data, "generator_version")
    sources = data.get("sources")

    genres_data = data.get("genres")
    if not isinstance(genres_data, Mapping) or not genres_data:
        raise ValueError("Genre profile artifact requires a non-empty genres object")

    profiles: dict[str, GenreProfile] = {}
    for raw_key, raw_profile in genres_data.items():
        key = normalize_genre(raw_key)
        if key in profiles:
            raise ValueError(f"Genre profile artifact has duplicate normalized genre {key!r}")
        if not isinstance(raw_profile, Mapping):
            raise ValueError(f"Genre profile {key!r} must be an object")
        sample_count = raw_profile.get("sample_count")
        if isinstance(sample_count, bool) or not isinstance(sample_count, int) or sample_count < 5:
            raise ValueError(f"Genre profile {key!r} sample_count must be at least 5")
        raw_metrics = raw_profile.get("metrics")
        if not isinstance(raw_metrics, Mapping) or set(raw_metrics) != set(SUPPORTED_METRICS):
            raise ValueError(f"Genre profile {key!r} must contain exactly the supported metrics")
        metrics: dict[str, MetricTarget] = {}
        for metric in SUPPORTED_METRICS:
            raw_target = raw_metrics[metric]
            if not isinstance(raw_target, Mapping):
                raise ValueError(f"Genre metric {metric!r} must be an object")
            try:
                metrics[metric] = _metric_target(raw_target)
            except (KeyError, TypeError, ValueError) as error:
                if isinstance(error, ValueError):
                    raise
                raise ValueError(f"Genre metric {metric!r} is incomplete") from error
        profiles[key] = GenreProfile(key, sample_count, MappingProxyType(metrics))

    _validated_source_recordings(sources, profiles)

    checksum = _required_string(data, "artifact_checksum")
    expected_checksum = _canonical_checksum(data)
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
