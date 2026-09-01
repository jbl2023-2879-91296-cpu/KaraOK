"""Immutable, validated genre-specific audio target profiles."""

from __future__ import annotations

import hashlib
import json
import math
from dataclasses import dataclass
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
    if not isinstance(sources, Mapping):
        raise ValueError("Genre profile artifact requires a sources object")
    _required_string(sources, "license")
    _required_string(sources, "citation_url")

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


def load_genre_profiles(
    path: str | Path = DEFAULT_GENRE_PROFILE_PATH,
) -> GenreProfileArtifact:
    """Load and validate a genre profile artifact from JSON."""

    profile_path = Path(path)
    try:
        data = json.loads(profile_path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ValueError(f"Genre profile file does not exist: {profile_path}") from error
    except json.JSONDecodeError as error:
        raise ValueError(f"Genre profile file is not valid JSON: {error}") from error
    return parse_genre_profile_artifact(data)
