"""Owner-scoped amplifier profile and recommendation persistence services."""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from typing import Any, Mapping

import jwt

from audio_thresholds import (
    load_control_priors,
    load_genre_profiles,
    load_thresholds,
    normalize_genre,
)
from settings_recommendations import (
    ALGORITHM_VERSION,
    AmplifierScale,
    KnobAdjustment,
    KnobSettings,
    RecommendationRequest,
    SafetySignals,
    SettingsRecommendation,
    generate_recommendation,
)

from ...common.validation import bounded_number


PROFILE_FIELDS = {
    "name",
    "scale_min",
    "scale_max",
    "scale_step",
    "last_positions",
}
SCALE_FIELDS = ("scale_min", "scale_max", "scale_step")
KNOB_NAMES = ("volume", "bass", "treble", "sharpness", "flatness")
GUEST_VERIFICATION_AUDIENCE = "karaok-guest-settings-verification"
GUEST_VERIFICATION_KIND = "guest_settings_verification"
GUEST_TOKEN_CLAIMS = {
    "kind",
    "genre",
    "scale",
    "recommended_positions",
    "before_score",
    "profile_version",
    "profile_checksum",
    "algorithm_version",
    "initial_pass",
    "aud",
    "iat",
    "exp",
}
GENRE_ARTIFACT_UNAVAILABLE_MESSAGE = (
    "Genre calibration data is temporarily unavailable. Please try again later; "
    "your audio quality result is still available."
)
MISSING_GENRE_PROFILE_MESSAGE = (
    "No supported genre calibration profile is available. Choose a supported "
    "genre and record again."
)


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


def parse_guest_verification_token(token: str) -> GuestVerificationContext:
    if not isinstance(token, str) or not token.strip():
        raise ValueError("verification_token is required")
    from ... import application

    try:
        claims = jwt.decode(
            token.strip(),
            application.JWT_SECRET,
            algorithms=["HS256"],
            audience=GUEST_VERIFICATION_AUDIENCE,
            options={"require": ["aud", "iat", "exp"]},
        )
    except jwt.InvalidTokenError as error:
        raise ValueError("verification_token is invalid or expired") from error
    if set(claims) != GUEST_TOKEN_CLAIMS:
        raise ValueError("verification_token has an invalid claim set")
    if claims.get("kind") != GUEST_VERIFICATION_KIND:
        raise ValueError("verification_token has an invalid kind")
    if claims.get("initial_pass") is not True:
        raise ValueError("verification_token is not an initial-pass token")

    artifact = load_genre_profiles()
    genre = normalize_genre(claims.get("genre"))
    if claims.get("profile_version") != artifact.profile_version:
        raise ValueError("verification_token profile version is unsupported")
    if claims.get("profile_checksum") != artifact.artifact_checksum:
        raise ValueError("verification_token profile checksum is unsupported")
    if claims.get("algorithm_version") != ALGORITHM_VERSION:
        raise ValueError("verification_token algorithm version is unsupported")
    scale_data = claims.get("scale")
    positions_data = claims.get("recommended_positions")
    if not isinstance(scale_data, Mapping) or not isinstance(positions_data, Mapping):
        raise ValueError("verification_token settings are invalid")
    scale = _amplifier_scale(scale_data, "verification_token.scale")
    positions = _knob_settings(
        positions_data,
        scale,
        "verification_token.recommended_positions",
    )
    before_score = _strict_number(
        claims.get("before_score"),
        "verification_token.before_score",
    )
    if not 0 <= before_score <= 100:
        raise ValueError("verification_token.before_score must be between 0 and 100")
    return GuestVerificationContext(
        genre=genre,
        scale=scale,
        recommended_positions=positions,
        before_score=before_score,
        profile_version=str(claims["profile_version"]),
        profile_checksum=str(claims["profile_checksum"]),
        algorithm_version=str(claims["algorithm_version"]),
    )


def issue_guest_verification_token(
    recommendation: SettingsRecommendation,
    scale: AmplifierScale,
    *,
    before_score: float,
) -> str:
    if recommendation.status != "generated":
        raise ValueError("Only a generated recommendation can be verified")
    recommended = {
        name: recommendation.adjustments[name].recommended for name in KNOB_NAMES
    }
    if any(value is None for value in recommended.values()):
        raise ValueError("Generated recommendation targets are incomplete")
    score = _strict_number(before_score, "before_score")
    if not 0 <= score <= 100:
        raise ValueError("before_score must be between 0 and 100")
    from ... import application

    now = datetime.now(timezone.utc)
    claims = {
        "kind": GUEST_VERIFICATION_KIND,
        "genre": recommendation.genre,
        "scale": scale.to_dict(),
        "recommended_positions": recommended,
        "before_score": score,
        "profile_version": recommendation.profile_version,
        "profile_checksum": recommendation.profile_checksum,
        "algorithm_version": recommendation.algorithm_version,
        "initial_pass": True,
        "aud": GUEST_VERIFICATION_AUDIENCE,
        "iat": now,
        "exp": now + timedelta(hours=24),
    }
    return jwt.encode(claims, application.JWT_SECRET, algorithm="HS256")


def parse_suggestion_form(
    form: Mapping[str, Any],
    *,
    guest: bool,
    user_id: int | None,
) -> SuggestionContext | None:
    purpose = form.get("analysis_purpose", "quality_evaluation")
    if purpose != "settings_suggestion":
        return None
    genre = normalize_genre(form.get("genre"))
    verification_of_raw = form.get("verification_of")
    token_raw = form.get("verification_token")
    has_verification_of = verification_of_raw not in (None, "")
    has_token = token_raw not in (None, "")
    if has_verification_of and has_token:
        raise ValueError("verification_of and verification_token are mutually exclusive")

    if guest:
        if user_id is not None:
            raise ValueError("Guest suggestion context cannot have a user")
        if form.get("amplifier_profile_id") not in (None, ""):
            raise ValueError("Guests must provide amplifier_scale, not a profile ID")
        if has_verification_of:
            raise ValueError("Guests must use verification_token")
        scale = _amplifier_scale(
            _json_object(form, "amplifier_scale"),
            "amplifier_scale",
        )
        current = _knob_settings(
            _json_object(form, "current_settings"),
            scale,
            "current_settings",
        )
        verification = (
            parse_guest_verification_token(str(token_raw)) if has_token else None
        )
        if verification is not None:
            if genre != verification.genre:
                raise ValueError("genre does not match verification_token")
            if not _same_scale(scale, verification.scale):
                raise ValueError("amplifier_scale does not match verification_token")
            if not _same_positions(current, verification.recommended_positions, scale):
                raise ValueError(
                    "current_settings must match the initial recommended positions"
                )
        return SuggestionContext(
            guest=True,
            user_id=None,
            genre=genre,
            scale=scale,
            current=current,
            guest_verification=verification,
            before_score=verification.before_score if verification else None,
        )

    if user_id is None:
        raise ValueError("Authenticated suggestion context requires a user")
    if has_token:
        raise ValueError("Authenticated verification must use verification_of")
    if form.get("amplifier_scale") not in (None, ""):
        raise ValueError("Authenticated suggestions must use an amplifier profile")
    profile_id = _positive_identifier(
        form.get("amplifier_profile_id"),
        "amplifier_profile_id",
    )
    verification_of = (
        _positive_identifier(verification_of_raw, "verification_of")
        if has_verification_of
        else None
    )

    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    try:
        profile = _select_profile(cursor, user_id, profile_id)
        if profile is None:
            raise ValueError("amplifier_profile_id is not owned by this user")
        scale = AmplifierScale(
            float(profile["scale_min"]),
            float(profile["scale_max"]),
            float(profile["scale_step"]),
        )
        if scale.step > scale.maximum - scale.minimum:
            raise ValueError("Stored amplifier profile scale_step exceeds its range")
        current = _knob_settings(
            _json_object(form, "current_settings"),
            scale,
            "current_settings",
        )
        before_score = None
        if verification_of is not None:
            cursor.execute(
                """SELECT sr.recommendation_id, sr.genre, sr.original_score,
                          sr.recommended_positions, sr.algorithm_version,
                          sr.genre_profile_version,
                          sr.genre_profile_checksum,
                          sr.scale_min, sr.scale_max, sr.scale_step,
                          sr.recommendation_status,
                          child.recommendation_id AS child_recommendation_id
                   FROM settings_recommendation sr
                   LEFT JOIN settings_recommendation child
                     ON child.parent_recommendation_id = sr.recommendation_id
                   WHERE sr.recommendation_id = %s AND sr.user_id = %s
                     AND sr.amplifier_profile_id = %s""",
                (verification_of, user_id, profile_id),
            )
            parent = cursor.fetchone()
            if parent is None:
                raise ValueError("verification_of is not owned by this user and profile")
            before_score = validate_authenticated_verification_binding(
                parent,
                profile,
                genre=genre,
                current=current,
                scale=scale,
            )
        return SuggestionContext(
            guest=False,
            user_id=user_id,
            genre=genre,
            scale=scale,
            current=current,
            amplifier_profile_id=profile_id,
            verification_of=verification_of,
            before_score=before_score,
        )
    finally:
        cursor.close()
        connection.close()


def _unavailable_recommendation(
    context: SuggestionContext,
    profile_version: str | None,
    profile_checksum: str | None,
    *,
    message: str,
) -> SettingsRecommendation:
    adjustments = {
        name: KnobAdjustment(
            current=getattr(context.current, name),
            recommended=None,
            delta=None,
            delta_normalized=None,
            reason_code="genre_profile_unavailable",
            confidence="unavailable",
        )
        for name in KNOB_NAMES
    }
    return SettingsRecommendation(
        status="unavailable",
        genre=context.genre,
        profile_version=profile_version,
        profile_checksum=profile_checksum,
        algorithm_version=ALGORITHM_VERSION,
        scale=context.scale,
        current=context.current,
        adjustments=adjustments,
        overall_confidence="unavailable",
        message=message,
    )


def build_recommendation(
    summary: Mapping[str, Any],
    context: SuggestionContext,
    *,
    verification: bool,
) -> SettingsRecommendation:
    if not isinstance(context, SuggestionContext):
        raise ValueError("context must be a SuggestionContext")
    if verification != context.verification:
        raise ValueError("verification flag does not match suggestion context")
    try:
        artifact = load_genre_profiles()
    except (OSError, TypeError, ValueError):
        return _unavailable_recommendation(
            context,
            None,
            None,
            message=GENRE_ARTIFACT_UNAVAILABLE_MESSAGE,
        )
    try:
        profile = artifact.profile_for(context.genre)
    except ValueError:
        return _unavailable_recommendation(
            context,
            artifact.profile_version,
            artifact.artifact_checksum,
            message=MISSING_GENRE_PROFILE_MESSAGE,
        )
    safety_data = summary.get("safety_signals", {})
    if not isinstance(safety_data, Mapping):
        safety_data = {}
    safety = SafetySignals(
        silent=bool(safety_data.get("silent", False)),
        corrupt=bool(safety_data.get("corrupt", False)),
        too_short=bool(safety_data.get("too_short", False)),
        clipping=bool(safety_data.get("clipping", False)),
        excessive_noise=bool(safety_data.get("excessive_noise", False)),
        excessive_distortion=bool(
            safety_data.get("excessive_distortion", False)
        ),
        low_confidence_metrics=frozenset(
            safety_data.get("low_confidence_metrics", ())
        ),
    )
    measurements = {
        name: summary.get(name)
        for name in ("loudness", "bass", "treble", "sharpness", "flatness")
    }
    request = RecommendationRequest(
        scale=context.scale,
        current=context.current,
        measurements=measurements,
        profile_version=artifact.profile_version,
        profile_checksum=artifact.artifact_checksum,
        safety=safety,
        verification=verification,
        hardware_response_characterized=False,
    )
    return generate_recommendation(request, profile)


def _connection():
    from ... import application

    return application.get_db()


def _finite_number(value: Any, field: str) -> float:
    return bounded_number(value, field, -9_999_999.999, 9_999_999.999)


def _name(value: Any) -> str:
    if not isinstance(value, str):
        raise ValueError("name must be text")
    cleaned = " ".join(value.strip().split())
    if not 1 <= len(cleaned) <= 80:
        raise ValueError("name must be 1-80 characters")
    return cleaned


def _scale(values: Mapping[str, Any]) -> tuple[float, float, float]:
    minimum = _finite_number(values["scale_min"], "scale_min")
    maximum = _finite_number(values["scale_max"], "scale_max")
    step = _finite_number(values["scale_step"], "scale_step")
    if minimum >= maximum:
        raise ValueError("scale_min must be less than scale_max")
    if step <= 0:
        raise ValueError("scale_step must be positive")
    if step > maximum - minimum:
        raise ValueError("scale_step must not exceed the scale range")
    return minimum, maximum, step


def _positions(
    value: Any,
    *,
    minimum: float,
    maximum: float,
) -> dict[str, float] | None:
    if value is None:
        return None
    if not isinstance(value, Mapping) or set(value) != set(KNOB_NAMES):
        raise ValueError("last_positions must contain exactly all five knob values")
    positions: dict[str, float] = {}
    for name in KNOB_NAMES:
        number = _finite_number(value[name], f"last_positions.{name}")
        if number < minimum or number > maximum:
            raise ValueError(
                f"last_positions.{name} must be between {minimum} and {maximum}"
            )
        positions[name] = number
    return positions


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


def _profile_response(row: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "id": int(row["amplifier_profile_id"]),
        "name": str(row["name"]),
        "scale_min": float(row["scale_min"]),
        "scale_max": float(row["scale_max"]),
        "scale_step": float(row["scale_step"]),
        "last_positions": _decoded_json(row.get("last_positions"), "last_positions"),
        "created_at": _json_safe(row.get("created_at")),
        "updated_at": _json_safe(row.get("updated_at")),
    }


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


def _select_profile(cursor, user_id: int, profile_id: int, *, lock: bool = False):
    cursor.execute(
        """SELECT amplifier_profile_id, user_id, name, scale_min, scale_max,
                  scale_step, last_positions, created_at, updated_at
           FROM amplifier_profile
           WHERE amplifier_profile_id = %s AND user_id = %s"""
        + (" FOR UPDATE" if lock else ""),
        (profile_id, user_id),
    )
    return cursor.fetchone()


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


def list_amplifier_profiles(user_id: int) -> list[dict[str, Any]]:
    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    try:
        cursor.execute(
            """SELECT amplifier_profile_id, user_id, name, scale_min, scale_max,
                      scale_step, last_positions, created_at, updated_at
               FROM amplifier_profile
               WHERE user_id = %s
               ORDER BY created_at, amplifier_profile_id""",
            (user_id,),
        )
        return [_profile_response(row) for row in cursor.fetchall()]
    finally:
        cursor.close()
        connection.close()


def get_amplifier_profile(user_id: int, profile_id: int) -> dict[str, Any]:
    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    try:
        row = _select_profile(cursor, user_id, profile_id)
        if row is None:
            raise LookupError("Amplifier profile was not found")
        return _profile_response(row)
    finally:
        cursor.close()
        connection.close()


def create_amplifier_profile(user_id: int, payload: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(payload, Mapping):
        raise ValueError("A JSON object is required")
    unexpected = set(payload).difference(PROFILE_FIELDS)
    if unexpected:
        raise ValueError(f"Profile contains unsupported fields: {sorted(unexpected)!r}")
    missing = {"name", *SCALE_FIELDS}.difference(payload)
    if missing:
        raise ValueError(f"Profile is missing required fields: {sorted(missing)!r}")

    name = _name(payload["name"])
    minimum, maximum, step = _scale(payload)
    positions = _positions(
        payload.get("last_positions"),
        minimum=minimum,
        maximum=maximum,
    )
    encoded_positions = (
        json.dumps(positions, sort_keys=True, separators=(",", ":"))
        if positions is not None
        else None
    )

    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    try:
        cursor.execute(
            """INSERT INTO amplifier_profile
               (user_id, name, scale_min, scale_max, scale_step, last_positions)
               VALUES (%s, %s, %s, %s, %s, %s)""",
            (user_id, name, minimum, maximum, step, encoded_positions),
        )
        profile_id = cursor.lastrowid
        row = _select_profile(cursor, user_id, profile_id)
        if row is None:
            raise RuntimeError("Created amplifier profile could not be loaded")
        connection.commit()
        return _profile_response(row)
    except Exception:
        connection.rollback()
        raise
    finally:
        cursor.close()
        connection.close()


def update_amplifier_profile(
    user_id: int,
    profile_id: int,
    payload: Mapping[str, Any],
) -> dict[str, Any]:
    if not isinstance(payload, Mapping) or not payload:
        raise ValueError("At least one profile field is required")
    unexpected = set(payload).difference(PROFILE_FIELDS)
    if unexpected:
        raise ValueError(f"Profile contains unsupported fields: {sorted(unexpected)!r}")

    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    rolled_back = False
    try:
        current = _select_profile(cursor, user_id, profile_id, lock=True)
        if current is None:
            connection.rollback()
            rolled_back = True
            raise LookupError("Amplifier profile was not found")

        effective = {
            "scale_min": payload.get("scale_min", current["scale_min"]),
            "scale_max": payload.get("scale_max", current["scale_max"]),
            "scale_step": payload.get("scale_step", current["scale_step"]),
        }
        minimum, maximum, step = _scale(effective)
        stored_positions = _decoded_json(current.get("last_positions"), "last_positions")
        positions = _positions(
            payload.get("last_positions", stored_positions),
            minimum=minimum,
            maximum=maximum,
        )

        updates: dict[str, Any] = {}
        if "name" in payload:
            updates["name"] = _name(payload["name"])
        for field, value in zip(SCALE_FIELDS, (minimum, maximum, step), strict=True):
            if field in payload:
                updates[field] = value
        if "last_positions" in payload:
            updates["last_positions"] = (
                json.dumps(positions, sort_keys=True, separators=(",", ":"))
                if positions is not None
                else None
            )

        cursor.execute(
            "UPDATE amplifier_profile SET "
            + ", ".join(f"{field} = %s" for field in updates)
            + ", updated_at = CURRENT_TIMESTAMP "
            + "WHERE amplifier_profile_id = %s AND user_id = %s",
            tuple(updates.values()) + (profile_id, user_id),
        )
        updated = _select_profile(cursor, user_id, profile_id)
        connection.commit()
        return _profile_response(updated)
    except Exception:
        if not rolled_back:
            connection.rollback()
        raise
    finally:
        cursor.close()
        connection.close()


def delete_amplifier_profile(user_id: int, profile_id: int) -> dict[str, Any]:
    connection = _connection()
    cursor = connection.cursor()
    rolled_back = False
    try:
        cursor.execute(
            """DELETE FROM amplifier_profile
               WHERE amplifier_profile_id = %s AND user_id = %s""",
            (profile_id, user_id),
        )
        if cursor.rowcount != 1:
            connection.rollback()
            rolled_back = True
            raise LookupError("Amplifier profile was not found")
        connection.commit()
        return {"id": profile_id, "message": "Amplifier profile deleted"}
    except Exception:
        if not rolled_back:
            connection.rollback()
        raise
    finally:
        cursor.close()
        connection.close()


def _recommendation_select(*, lock: bool) -> str:
    return (
        """SELECT sr.recommendation_id, sr.user_id, sr.assessment_id,
                  sr.amplifier_profile_id, sr.parent_recommendation_id,
                  sr.genre, sr.current_positions, sr.recommended_positions,
                  sr.adjustments, sr.original_score, sr.verification_score,
                  sr.overall_confidence, sr.algorithm_version,
                  sr.genre_profile_version, sr.genre_profile_checksum,
                  sr.unavailable_message,
                  sr.recommendation_status,
                  sr.created_at, sr.applied_at,
                  sr.scale_min, sr.scale_max, sr.scale_step,
                  ap.scale_min AS profile_scale_min,
                  ap.scale_max AS profile_scale_max,
                  ap.scale_step AS profile_scale_step
           FROM settings_recommendation sr
           JOIN amplifier_profile ap
             ON ap.amplifier_profile_id = sr.amplifier_profile_id
            AND ap.user_id = sr.user_id
           WHERE sr.recommendation_id = %s
             AND sr.user_id = %s
             AND ap.user_id = %s"""
        + (" FOR UPDATE" if lock else "")
    )


def get_owned_recommendation(user_id: int, recommendation_id: int) -> dict[str, Any]:
    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    try:
        cursor.execute(
            _recommendation_select(lock=False),
            (recommendation_id, user_id, user_id),
        )
        row = cursor.fetchone()
        if row is None:
            raise LookupError("Settings recommendation was not found")
        return _recommendation_response(row)
    finally:
        cursor.close()
        connection.close()


def mark_recommendation_applied(
    user_id: int,
    recommendation_id: int,
) -> dict[str, Any]:
    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    rolled_back = False
    try:
        cursor.execute(
            _recommendation_select(lock=True),
            (recommendation_id, user_id, user_id),
        )
        row = cursor.fetchone()
        if row is None:
            connection.rollback()
            rolled_back = True
            raise LookupError("Settings recommendation was not found")
        if row["recommendation_status"] != "generated":
            connection.rollback()
            rolled_back = True
            raise ConflictError("Only a generated recommendation can be applied")

        snapshot_scale = _stored_scale(row)
        profile_scale = _stored_scale(row, prefix="profile_")
        if not _same_scale(snapshot_scale, profile_scale):
            connection.rollback()
            rolled_back = True
            raise ConflictError(
                "Amplifier profile scale changed after this recommendation was generated"
            )

        recommended = _decoded_json(
            row["recommended_positions"], "recommended_positions"
        )
        parsed_positions = _knob_settings(
            recommended,
            snapshot_scale,
            "recommended_positions",
        )
        encoded_positions = json.dumps(
            parsed_positions.to_dict(),
            sort_keys=True,
            separators=(",", ":"),
        )
        cursor.execute(
            """UPDATE amplifier_profile
               SET last_positions = %s, updated_at = CURRENT_TIMESTAMP
               WHERE amplifier_profile_id = %s AND user_id = %s""",
            (encoded_positions, row["amplifier_profile_id"], user_id),
        )
        cursor.execute(
            """UPDATE settings_recommendation
               SET recommendation_status = 'applied',
                   applied_at = UTC_TIMESTAMP()
               WHERE recommendation_id = %s AND user_id = %s
                 AND recommendation_status = 'generated'""",
            (recommendation_id, user_id),
        )
        if cursor.rowcount != 1:
            raise ConflictError("Recommendation state changed before it was applied")
        connection.commit()

        applied = dict(row)
        applied["recommendation_status"] = "applied"
        applied["applied_at"] = datetime.now(timezone.utc)
        return _recommendation_response(applied)
    except Exception:
        if not rolled_back:
            connection.rollback()
        raise
    finally:
        cursor.close()
        connection.close()
