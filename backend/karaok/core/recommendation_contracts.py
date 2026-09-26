"""Recommendation contracts implementation."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from datetime import datetime
from decimal import Decimal
from karaok.core.recommendation_models import ALGORITHM_VERSION
from karaok.core.recommendation_models import AmplifierScale
from karaok.core.recommendation_models import KnobSettings
from karaok.core.recommendation_models import SettingsRecommendation
from karaok.core.thresholds import load_control_priors
from karaok.core.thresholds import load_genre_profiles
from karaok.core.thresholds import load_thresholds
from karaok.core.thresholds import normalize_genre
from typing import Any
from typing import Mapping
import json
import math


KNOB_NAMES = ("volume", "bass", "treble", "sharpness", "flatness")


class ConflictError(RuntimeError):
    """Raised when valid input conflicts with the current resource state."""


@dataclass(frozen=True)
class GuestVerificationContext:
    genre: str
    scale: AmplifierScale
    recommended_positions: KnobSettings
    before_score: float
    profile_version: str
    profile_checksum: str
    algorithm_version: str


@dataclass(frozen=True)
class SuggestionContext:
    guest: bool
    user_id: int | None
    genre: str
    scale: AmplifierScale
    current: KnobSettings
    amplifier_profile_id: int | None = None
    verification_of: int | None = None
    guest_verification: GuestVerificationContext | None = None
    before_score: float | None = None

    @property
    def verification(self) -> bool:
        return self.verification_of is not None or self.guest_verification is not None


def _strict_number(value: Any, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{field} must be a finite number")
    number = float(value)
    if not math.isfinite(number):
        raise ValueError(f"{field} must be a finite number")
    return number


def _json_object(form: Mapping[str, Any], field: str) -> Mapping[str, Any]:
    raw = form.get(field)
    if not isinstance(raw, str) or not raw.strip():
        raise ValueError(f"{field} is required")
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as error:
        raise ValueError(f"{field} must be valid JSON") from error
    if not isinstance(value, Mapping):
        raise ValueError(f"{field} must be a JSON object")
    return value


def _amplifier_scale(value: Mapping[str, Any], field: str) -> AmplifierScale:
    if set(value) != {"minimum", "maximum", "step"}:
        raise ValueError(f"{field} must contain exactly minimum, maximum, and step")
    scale = AmplifierScale(
        _strict_number(value["minimum"], f"{field}.minimum"),
        _strict_number(value["maximum"], f"{field}.maximum"),
        _strict_number(value["step"], f"{field}.step"),
    )
    if scale.step > scale.maximum - scale.minimum:
        raise ValueError(f"{field}.step must not exceed the scale range")
    return scale


def _knob_settings(
    value: Mapping[str, Any],
    scale: AmplifierScale,
    field: str,
) -> KnobSettings:
    if set(value) != set(KNOB_NAMES):
        raise ValueError(f"{field} must contain exactly all five knob values")
    positions = {
        name: scale.validate(_strict_number(value[name], f"{field}.{name}"))
        for name in KNOB_NAMES
    }
    return KnobSettings(**positions)


def _positive_identifier(value: Any, field: str) -> int:
    try:
        identifier = int(str(value).strip())
    except (TypeError, ValueError) as error:
        raise ValueError(f"{field} must be a positive integer") from error
    if identifier < 1 or str(identifier) != str(value).strip():
        raise ValueError(f"{field} must be a positive integer")
    return identifier


def _same_scale(left: AmplifierScale, right: AmplifierScale) -> bool:
    return all(
        math.isclose(
            getattr(left, field),
            getattr(right, field),
            rel_tol=0.0,
            abs_tol=1e-12,
        )
        for field in ("minimum", "maximum", "step")
    )


def _quantized_step_index(value: float, scale: AmplifierScale) -> int:
    quantized = scale.denormalize(scale.normalize(value))
    return round((quantized - scale.minimum) / scale.step)


def _same_positions(
    left: KnobSettings,
    right: KnobSettings,
    scale: AmplifierScale,
) -> bool:
    return all(
        _quantized_step_index(getattr(left, name), scale)
        == _quantized_step_index(getattr(right, name), scale)
        for name in KNOB_NAMES
    )


def _stored_scale(row: Mapping[str, Any], *, prefix: str = "") -> AmplifierScale:
    scale = AmplifierScale(
        float(row[f"{prefix}scale_min"]),
        float(row[f"{prefix}scale_max"]),
        float(row[f"{prefix}scale_step"]),
    )
    if scale.step > scale.maximum - scale.minimum:
        raise ValueError("Stored amplifier profile scale_step exceeds its range")
    return scale


def validate_profile_scale_snapshot(
    profile: Mapping[str, Any],
    snapshot: AmplifierScale,
) -> None:
    if not _same_scale(_stored_scale(profile), snapshot):
        raise ValueError("amplifier profile scale changed before recommendation was saved")


def validate_authenticated_verification_binding(
    parent: Mapping[str, Any],
    profile: Mapping[str, Any],
    *,
    genre: str,
    current: KnobSettings,
    scale: AmplifierScale,
    require_current_artifact: bool = True,
) -> float:
    """Bind an authenticated verification to the still-applied parent state."""
    if parent["recommendation_status"] != "applied":
        raise ValueError("verification_of must reference an applied recommendation")
    if parent.get("child_recommendation_id") is not None:
        raise ValueError("verification_of already has a verification result")
    if normalize_genre(parent["genre"]) != genre:
        raise ValueError("genre does not match verification_of")

    if require_current_artifact:
        artifact = load_genre_profiles()
        if (
            parent.get("genre_profile_version") != artifact.profile_version
            or parent.get("genre_profile_checksum") != artifact.artifact_checksum
        ):
            raise ValueError(
                "verification_of profile version or profile checksum does not match "
                "the validated artifact"
            )
    if parent.get("algorithm_version") != ALGORITHM_VERSION:
        raise ValueError("verification_of algorithm version is unsupported")

    parent_scale = _stored_scale(parent)
    profile_scale = _stored_scale(profile)
    if not _same_scale(parent_scale, profile_scale):
        raise ValueError("amplifier profile scale changed before verification")
    if not _same_scale(scale, parent_scale):
        raise ValueError("amplifier scale does not match verification_of snapshot")

    recommended_data = _decoded_json(
        parent.get("recommended_positions"),
        "recommended_positions",
    )
    if not isinstance(recommended_data, Mapping):
        raise ValueError("verification_of recommended_positions are invalid")
    recommended = _knob_settings(
        recommended_data,
        parent_scale,
        "verification_of.recommended_positions",
    )
    if not _same_positions(current, recommended, parent_scale):
        raise ValueError(
            "current_settings must match verification_of recommended_positions"
        )

    last_positions_data = _decoded_json(
        profile.get("last_positions"),
        "last_positions",
    )
    if not isinstance(last_positions_data, Mapping):
        raise ValueError(
            "amplifier profile last_positions must match verification_of "
            "recommended_positions"
        )
    last_positions = _knob_settings(
        last_positions_data,
        parent_scale,
        "amplifier_profile.last_positions",
    )
    if not _same_positions(last_positions, recommended, parent_scale):
        raise ValueError(
            "amplifier profile last_positions must match verification_of "
            "recommended_positions"
        )
    return _strict_number(parent["original_score"], "original_score")


def _decoded_json(value: Any, field: str) -> Any:
    if value is None or isinstance(value, (dict, list)):
        return value
    if isinstance(value, bytes):
        value = value.decode("utf-8")
    if isinstance(value, str):
        try:
            return json.loads(value)
        except json.JSONDecodeError as error:
            raise ValueError(f"Stored {field} is not valid JSON") from error
    raise ValueError(f"Stored {field} has an unsupported value")


def _json_safe(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    return value


def _score_comparison(
    before_score: float,
    after_score: float | None,
) -> dict[str, Any]:
    if after_score is None:
        return {
            "before_score": before_score,
            "after_score": None,
            "score_change": None,
            "verification_status": "not_verified",
            "rollback_recommended": False,
        }
    change = round(after_score - before_score, 6)
    if change > 0:
        status = "improved"
    elif change < 0:
        status = "worsened"
    else:
        status = "unchanged"
    return {
        "before_score": before_score,
        "after_score": after_score,
        "score_change": change,
        "verification_status": status,
        "rollback_recommended": change < 0,
    }


def recommendation_payload(
    recommendation: SettingsRecommendation,
    context: SuggestionContext,
    *,
    score: float,
    recommendation_id: int | None,
    persisted: bool,
    verification_token: str | None = None,
) -> dict[str, Any]:
    measured_score = _strict_number(score, "score")
    before_score = (
        _strict_number(context.before_score, "before_score")
        if context.verification
        else measured_score
    )
    after_score = measured_score if context.verification else None
    payload = recommendation.to_dict()
    payload.update(
        {
            "id": recommendation_id,
            "persisted": persisted,
            "amplifier_profile_id": context.amplifier_profile_id,
            "parent_recommendation_id": context.verification_of,
            "original_score": before_score,
            "verification_score": after_score,
            "verification_token": verification_token,
            **_score_comparison(before_score, after_score),
        }
    )
    return payload


def _recommendation_response(row: Mapping[str, Any]) -> dict[str, Any]:
    original_score = float(row["original_score"])
    verification_score = (
        float(row["verification_score"])
        if row.get("verification_score") is not None
        else None
    )
    status = str(row["recommendation_status"])
    profile_version = row.get("genre_profile_version")
    profile_checksum = row.get("genre_profile_checksum")
    if status != "unavailable" and (
        not isinstance(profile_version, str) or not isinstance(profile_checksum, str)
    ):
        raise ValueError("Stored available recommendation is missing profile provenance")
    message = row.get("unavailable_message")
    response = {
        "id": int(row["recommendation_id"]),
        "persisted": True,
        "assessment_id": int(row["assessment_id"]),
        "amplifier_profile_id": int(row["amplifier_profile_id"]),
        "parent_recommendation_id": (
            int(row["parent_recommendation_id"])
            if row.get("parent_recommendation_id") is not None
            else None
        ),
        "genre": str(row["genre"]),
        "scale": {
            "minimum": float(row["scale_min"]),
            "maximum": float(row["scale_max"]),
            "step": float(row["scale_step"]),
        },
        "current": _decoded_json(row["current_positions"], "current_positions"),
        "recommended": _decoded_json(
            row["recommended_positions"], "recommended_positions"
        ),
        "adjustments": _decoded_json(row["adjustments"], "adjustments"),
        "original_score": original_score,
        "verification_score": verification_score,
        "overall_confidence": str(row["overall_confidence"]),
        "algorithm_version": str(row["algorithm_version"]),
        "profile_version": str(profile_version) if profile_version is not None else None,
        "profile_checksum": str(profile_checksum) if profile_checksum is not None else None,
        "status": status,
        "created_at": _json_safe(row.get("created_at")),
        "applied_at": _json_safe(row.get("applied_at")),
        "verification_token": None,
    }
    if message is not None:
        response["message"] = str(message)
    response.update(_score_comparison(original_score, verification_score))
    return response


def stored_recommendation_payload(row: Mapping[str, Any]) -> dict[str, Any] | None:
    if row.get("settings_recommendation_id") is None:
        return None
    names = (
        "recommendation_id",
        "assessment_id",
        "amplifier_profile_id",
        "parent_recommendation_id",
        "genre",
        "current_positions",
        "recommended_positions",
        "adjustments",
        "original_score",
        "verification_score",
        "overall_confidence",
        "algorithm_version",
        "genre_profile_version",
        "genre_profile_checksum",
        "unavailable_message",
        "recommendation_status",
        "created_at",
        "applied_at",
        "scale_min",
        "scale_max",
        "scale_step",
    )
    recommendation_row = {
        name: row.get(f"settings_{name}") for name in names
    }
    return _recommendation_response(recommendation_row)


def get_profile_metadata() -> dict[str, Any]:
    genre = load_genre_profiles()
    quality = load_thresholds()
    priors = load_control_priors()
    return {
        "profile_version": genre.profile_version,
        "profile_checksum": genre.artifact_checksum,
        "quality_profile_version": quality["quality_profile_version"],
        "quality_profile_checksum": quality["artifact_checksum"],
        "enabled_genres": sorted(genre.genres),
        "control_priors": priors.to_metadata(),
    }
