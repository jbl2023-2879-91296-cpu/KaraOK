"""Immutable request and result models for amplifier recommendations."""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from types import MappingProxyType
from typing import Any, Mapping


KNOB_NAMES = ("volume", "bass", "treble", "sharpness", "flatness")
MEASUREMENT_NAMES = ("loudness", "bass", "treble", "sharpness", "flatness")
CONFIDENCE_LEVELS = ("high", "medium", "low", "unavailable")
_LOWERCASE_HEXADECIMAL = frozenset("0123456789abcdef")


def _finite_number(value: Any, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{name} must be a finite number")
    number = float(value)
    if not math.isfinite(number):
        raise ValueError(f"{name} must be a finite number")
    return number


def _profile_checksum(value: Any) -> str:
    if (
        not isinstance(value, str)
        or len(value) != 64
        or any(character not in _LOWERCASE_HEXADECIMAL for character in value)
    ):
        raise ValueError(
            "Recommendation profile_checksum must be exactly 64 lowercase "
            "hexadecimal characters"
        )
    return value


@dataclass(frozen=True)
class AmplifierScale:
    minimum: float
    maximum: float
    step: float

    def __post_init__(self) -> None:
        minimum = _finite_number(self.minimum, "scale minimum")
        maximum = _finite_number(self.maximum, "scale maximum")
        step = _finite_number(self.step, "scale step")
        if minimum >= maximum:
            raise ValueError("Amplifier scale minimum must be less than maximum")
        if step <= 0:
            raise ValueError("Amplifier scale step must be positive")
        object.__setattr__(self, "minimum", minimum)
        object.__setattr__(self, "maximum", maximum)
        object.__setattr__(self, "step", step)

    def validate(self, value: float) -> float:
        number = _finite_number(value, "amplifier position")
        if number < self.minimum or number > self.maximum:
            raise ValueError(
                f"Amplifier position must be between {self.minimum} and {self.maximum}"
            )
        return number

    def normalize(self, value: float) -> float:
        number = self.validate(value)
        return 100.0 * (number - self.minimum) / (self.maximum - self.minimum)

    def denormalize(self, value: float) -> float:
        normalized = _finite_number(value, "normalized amplifier position")
        clamped = min(100.0, max(0.0, normalized))
        raw = self.minimum + clamped * (self.maximum - self.minimum) / 100.0
        steps = round((raw - self.minimum) / self.step)
        rounded = self.minimum + steps * self.step
        return round(min(self.maximum, max(self.minimum, rounded)), 12)

    def to_dict(self) -> dict[str, float]:
        return {
            "minimum": self.minimum,
            "maximum": self.maximum,
            "step": self.step,
        }


@dataclass(frozen=True)
class KnobSettings:
    volume: float
    bass: float
    treble: float
    sharpness: float
    flatness: float

    def __post_init__(self) -> None:
        for name in KNOB_NAMES:
            object.__setattr__(self, name, _finite_number(getattr(self, name), name))

    def items(self) -> tuple[tuple[str, float], ...]:
        return tuple((name, getattr(self, name)) for name in KNOB_NAMES)

    def to_dict(self) -> dict[str, float]:
        return dict(self.items())


@dataclass(frozen=True)
class SafetySignals:
    silent: bool = False
    corrupt: bool = False
    too_short: bool = False
    clipping: bool = False
    excessive_noise: bool = False
    excessive_distortion: bool = False
    low_confidence_metrics: frozenset[str] = field(default_factory=frozenset)

    def __post_init__(self) -> None:
        for name in (
            "silent",
            "corrupt",
            "too_short",
            "clipping",
            "excessive_noise",
            "excessive_distortion",
        ):
            if not isinstance(getattr(self, name), bool):
                raise ValueError(f"Safety signal {name!r} must be boolean")
        metrics = frozenset(self.low_confidence_metrics)
        unknown = metrics.difference(MEASUREMENT_NAMES)
        if unknown:
            raise ValueError(
                f"Unknown low-confidence measurement names: {sorted(unknown)!r}"
            )
        object.__setattr__(self, "low_confidence_metrics", metrics)


@dataclass(frozen=True)
class RecommendationRequest:
    scale: AmplifierScale
    current: KnobSettings
    measurements: Mapping[str, float]
    profile_version: str
    profile_checksum: str
    safety: SafetySignals = field(default_factory=SafetySignals)
    verification: bool = False
    hardware_response_characterized: bool = False

    def __post_init__(self) -> None:
        if not isinstance(self.scale, AmplifierScale):
            raise ValueError("Recommendation scale must be an AmplifierScale")
        if not isinstance(self.current, KnobSettings):
            raise ValueError("Recommendation current settings must be KnobSettings")
        if not isinstance(self.safety, SafetySignals):
            raise ValueError("Recommendation safety signals must be SafetySignals")
        if not isinstance(self.verification, bool):
            raise ValueError("Recommendation verification flag must be boolean")
        if not isinstance(self.hardware_response_characterized, bool):
            raise ValueError(
                "Recommendation hardware_response_characterized flag must be boolean"
            )
        if not isinstance(self.profile_version, str) or not self.profile_version.strip():
            raise ValueError("Recommendation profile_version must be non-empty")
        if not isinstance(self.measurements, Mapping):
            raise ValueError("Recommendation measurements must be a mapping")
        for name, value in self.current.items():
            try:
                self.scale.validate(value)
            except ValueError as error:
                raise ValueError(f"Current {name} position is invalid: {error}") from error
        object.__setattr__(self, "profile_version", self.profile_version.strip())
        object.__setattr__(self, "profile_checksum", _profile_checksum(self.profile_checksum))
        object.__setattr__(
            self,
            "measurements",
            MappingProxyType(dict(self.measurements)),
        )


@dataclass(frozen=True)
class KnobAdjustment:
    current: float
    recommended: float | None
    delta: float | None
    delta_normalized: float | None
    reason_code: str
    confidence: str

    def __post_init__(self) -> None:
        if self.confidence not in CONFIDENCE_LEVELS:
            raise ValueError(f"Unsupported confidence level: {self.confidence!r}")
        if not isinstance(self.reason_code, str) or not self.reason_code:
            raise ValueError("Knob adjustment reason_code must be non-empty")

    def to_dict(self) -> dict[str, Any]:
        return {
            "current": self.current,
            "recommended": self.recommended,
            "delta": self.delta,
            "delta_normalized": self.delta_normalized,
            "reason_code": self.reason_code,
            "confidence": self.confidence,
        }


@dataclass(frozen=True)
class SettingsRecommendation:
    status: str
    genre: str
    profile_version: str | None
    profile_checksum: str | None
    algorithm_version: str
    scale: AmplifierScale
    current: KnobSettings
    adjustments: Mapping[str, KnobAdjustment]
    overall_confidence: str
    message: str | None = None

    def __post_init__(self) -> None:
        if self.status not in {"generated", "unavailable"}:
            raise ValueError(f"Unsupported recommendation status: {self.status!r}")
        if (self.profile_version is None) != (self.profile_checksum is None):
            raise ValueError(
                "Recommendation profile version and checksum must both be present or absent"
            )
        if self.status == "generated" and self.profile_version is None:
            raise ValueError("Generated recommendations require genre profile provenance")
        if self.profile_version is not None:
            if not isinstance(self.profile_version, str) or not self.profile_version.strip():
                raise ValueError("Recommendation profile_version must be non-empty")
            object.__setattr__(self, "profile_version", self.profile_version.strip())
            object.__setattr__(
                self,
                "profile_checksum",
                _profile_checksum(self.profile_checksum),
            )
        if self.message is not None and (
            not isinstance(self.message, str) or not self.message.strip()
        ):
            raise ValueError("Recommendation message must be non-empty text")
        if self.overall_confidence not in CONFIDENCE_LEVELS:
            raise ValueError(
                f"Unsupported overall confidence: {self.overall_confidence!r}"
            )
        if set(self.adjustments) != set(KNOB_NAMES):
            raise ValueError("A recommendation must contain exactly all five knobs")
        object.__setattr__(
            self,
            "adjustments",
            MappingProxyType(dict(self.adjustments)),
        )

    def to_dict(self) -> dict[str, Any]:
        adjustments = {
            name: self.adjustments[name].to_dict() for name in KNOB_NAMES
        }
        payload = {
            "status": self.status,
            "genre": self.genre,
            "profile_version": self.profile_version,
            "profile_checksum": self.profile_checksum,
            "algorithm_version": self.algorithm_version,
            "overall_confidence": self.overall_confidence,
            "scale": self.scale.to_dict(),
            "current": self.current.to_dict(),
            "recommended": {
                name: adjustments[name]["recommended"] for name in KNOB_NAMES
            },
            "adjustments": adjustments,
        }
        if self.message is not None:
            payload["message"] = self.message.strip()
        return payload


ALGORITHM_VERSION = "1.0.0"
