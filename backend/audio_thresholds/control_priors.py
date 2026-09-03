"""Immutable researched normalized amplifier-control starting positions."""

from __future__ import annotations

import json
import math
import re
from collections.abc import Mapping
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from types import MappingProxyType
from typing import Any

from .artifact_integrity import canonical_artifact_checksum


CONTROL_NAMES = ("volume", "bass", "treble", "sharpness", "flatness")
ARTIFACT_KEYS = {
    "schema_version",
    "prior_version",
    "normalized_scale",
    "positions",
    "requires_physical_confirmation",
    "assumptions",
    "sources",
    "artifact_checksum",
}
DEFAULT_CONTROL_PRIOR_PATH = Path(__file__).with_name("amplifier_control_priors.json")


@dataclass(frozen=True)
class ControlPriorArtifact:
    """Validated, immutable control-prior artifact."""

    prior_version: str
    artifact_checksum: str
    normalized_scale: Mapping[str, float]
    positions: Mapping[str, float]
    requires_physical_confirmation: bool

    def to_metadata(self) -> dict[str, Any]:
        """Return the public, citation-free metadata contract."""

        return {
            "prior_version": self.prior_version,
            "artifact_checksum": self.artifact_checksum,
            "normalized_scale": dict(self.normalized_scale),
            "positions": dict(self.positions),
            "requires_physical_confirmation": self.requires_physical_confirmation,
        }


def _finite(value: Any, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{field} must be a finite number")
    number = float(value)
    if not math.isfinite(number):
        raise ValueError(f"{field} must be a finite number")
    return number


def parse_control_priors(data: Mapping[str, Any]) -> ControlPriorArtifact:
    """Validate a JSON-compatible researched starting-position artifact."""

    if set(data) != ARTIFACT_KEYS:
        raise ValueError("Control-prior artifact fields do not match schema")
    if (
        isinstance(data.get("schema_version"), bool)
        or not isinstance(data.get("schema_version"), int)
        or data["schema_version"] != 1
    ):
        raise ValueError("Unsupported control-prior schema_version; expected 1")

    version = data.get("prior_version")
    checksum = data.get("artifact_checksum")
    if not isinstance(version, str) or not version.strip():
        raise ValueError("Control priors require prior_version")
    if not isinstance(checksum, str) or re.fullmatch(r"[0-9a-f]{64}", checksum) is None:
        raise ValueError("Control priors require a SHA-256 artifact_checksum")
    if checksum != canonical_artifact_checksum(data):
        raise ValueError("Control-prior artifact checksum does not match canonical content")

    scale = data.get("normalized_scale")
    positions = data.get("positions")
    if not isinstance(scale, Mapping) or set(scale) != {"minimum", "maximum"}:
        raise ValueError("Control priors require an exact normalized_scale")
    parsed_scale = {
        key: _finite(scale[key], f"normalized_scale.{key}") for key in scale
    }
    if parsed_scale != {"minimum": 0.0, "maximum": 100.0}:
        raise ValueError("Control-prior normalized_scale must be 0-100")

    if not isinstance(positions, Mapping) or set(positions) != set(CONTROL_NAMES):
        raise ValueError("Control priors require exactly all five controls")
    parsed_positions = {
        name: _finite(positions[name], f"positions.{name}") for name in CONTROL_NAMES
    }
    if any(value < 0.0 or value > 100.0 for value in parsed_positions.values()):
        raise ValueError("Control-prior positions must be within 0-100")

    if data.get("requires_physical_confirmation") is not True:
        raise ValueError("Control priors must require physical confirmation")
    for field in ("assumptions", "sources"):
        value = data.get(field)
        if not isinstance(value, list) or not value:
            raise ValueError(f"Control priors require non-empty {field}")
    if any(
        not isinstance(item, str) or not item.strip() for item in data["assumptions"]
    ):
        raise ValueError("Control-prior assumptions must be non-empty strings")
    for source in data["sources"]:
        if not isinstance(source, Mapping) or set(source) != {
            "title",
            "url",
            "supports",
        }:
            raise ValueError("Control-prior sources must match the source schema")
        if any(
            not isinstance(source[key], str) or not source[key].strip()
            for key in ("title", "url", "supports")
        ):
            raise ValueError("Control-prior source fields must be non-empty strings")

    return ControlPriorArtifact(
        prior_version=version.strip(),
        artifact_checksum=checksum,
        normalized_scale=MappingProxyType(parsed_scale),
        positions=MappingProxyType(parsed_positions),
        requires_physical_confirmation=True,
    )


@lru_cache(maxsize=None)
def _load_control_priors(path: str) -> ControlPriorArtifact:
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError) as error:
        raise ValueError(f"Control-prior artifact is unavailable: {error}") from error
    if not isinstance(data, Mapping):
        raise ValueError("Control-prior artifact must be an object")
    return parse_control_priors(data)


def clear_control_prior_cache() -> None:
    """Clear the cached artifact for isolated tests or explicit reloads."""

    _load_control_priors.cache_clear()


def load_control_priors(
    path: str | Path = DEFAULT_CONTROL_PRIOR_PATH,
) -> ControlPriorArtifact:
    """Load and validate the researched normalized starting positions."""

    return _load_control_priors(str(Path(path).resolve()))
