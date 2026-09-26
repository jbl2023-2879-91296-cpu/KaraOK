"""Recommendations implementation."""

from __future__ import annotations

from karaok.core.thresholds import load_genre_profiles
from karaok.core.thresholds import normalize_genre
from datetime import datetime
from datetime import timedelta
from datetime import timezone
from karaok.core.config import JWT_SECRET
from karaok.core.recommendation_contracts import GuestVerificationContext
from karaok.core.recommendation_contracts import KNOB_NAMES
from karaok.core.recommendation_contracts import SuggestionContext
from karaok.core.recommendation_contracts import _amplifier_scale
from karaok.core.recommendation_contracts import _json_object
from karaok.core.recommendation_contracts import _knob_settings
from karaok.core.recommendation_contracts import _positive_identifier
from karaok.core.recommendation_contracts import _same_positions
from karaok.core.recommendation_contracts import _same_scale
from karaok.core.recommendation_contracts import _strict_number
from karaok.core.recommendation_contracts import recommendation_payload
from karaok.core.recommendation_contracts import validate_authenticated_verification_binding
from karaok.results.database import _connection
from karaok.results.profiles import _select_profile
from karaok.core.recommendation_models import ALGORITHM_VERSION
from karaok.core.recommendation_models import AmplifierScale
from karaok.core.recommendation_models import KnobAdjustment
from karaok.core.recommendation_models import RecommendationRequest
from karaok.core.recommendation_models import SafetySignals
from karaok.core.recommendation_models import SettingsRecommendation
from settings_recommendations import generate_recommendation
from typing import Any
from typing import Mapping
import jwt


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


def parse_guest_verification_token(token: str) -> GuestVerificationContext:
    if not isinstance(token, str) or not token.strip():
        raise ValueError("verification_token is required")

    try:
        claims = jwt.decode(
            token.strip(),
            JWT_SECRET,
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
    return jwt.encode(claims, JWT_SECRET, algorithm="HS256")


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
