"""Pure bounded recommendation engine for physical amplifier controls."""

from __future__ import annotations

import math
from collections.abc import Mapping
from types import MappingProxyType

from audio_thresholds.genre_profiles import (
    INSTRUMENTAL_STATUSES,
    GenreProfile,
    MetricTarget,
)

from .models import (
    KNOB_NAMES,
    MEASUREMENT_NAMES,
    KnobAdjustment,
    RecommendationRequest,
    SettingsRecommendation,
)


from karaok.core.recommendation_models import ALGORITHM_VERSION
SENSITIVITY_NORMALIZED = 15.0
INITIAL_DELTA_CAP = 15.0
VERIFICATION_DELTA_CAP = 7.5

KNOB_TO_METRIC = MappingProxyType(
    {
        "volume": "loudness",
        "bass": "bass",
        "treble": "treble",
        "sharpness": "sharpness",
        "flatness": "flatness",
    }
)
MONOTONIC_DIRECTION = MappingProxyType({name: 1.0 for name in KNOB_NAMES})
CROSS_COUPLED_KNOBS = frozenset({"bass", "treble", "sharpness", "flatness"})
_CONFIDENCE_SCORE = {"low": 0, "medium": 1, "high": 2}
_SCORE_CONFIDENCE = {score: name for name, score in _CONFIDENCE_SCORE.items()}


def _clamp(value: float, minimum: float, maximum: float) -> float:
    return min(maximum, max(minimum, value))


def _invalid_recording_reason(request: RecommendationRequest) -> str | None:
    if request.safety.silent:
        return "silent_recording"
    if request.safety.corrupt:
        return "corrupt_recording"
    if request.safety.too_short:
        return "recording_too_short"
    return None


def _valid_target(target: object) -> bool:
    if not isinstance(target, MetricTarget):
        return False
    values = (target.lower, target.preferred, target.upper, target.robust_scale)
    return (
        all(
            not isinstance(value, bool)
            and isinstance(value, (int, float))
            and math.isfinite(float(value))
            for value in values
        )
        and target.lower < target.preferred < target.upper
        and target.robust_scale > 0
    )


def _unavailable(
    request: RecommendationRequest,
    profile: GenreProfile,
    reason_code: str,
) -> SettingsRecommendation:
    adjustments = {
        name: KnobAdjustment(
            current=getattr(request.current, name),
            recommended=None,
            delta=None,
            delta_normalized=None,
            reason_code=reason_code,
            confidence="unavailable",
        )
        for name in KNOB_NAMES
    }
    return SettingsRecommendation(
        status="unavailable",
        genre=profile.key,
        profile_version=request.profile_version,
        profile_checksum=request.profile_checksum,
        algorithm_version=ALGORITHM_VERSION,
        scale=request.scale,
        current=request.current,
        adjustments=adjustments,
        overall_confidence="unavailable",
    )


def _preflight_reason(
    request: RecommendationRequest,
    profile: GenreProfile,
) -> str | None:
    invalid_recording = _invalid_recording_reason(request)
    if invalid_recording:
        return invalid_recording

    if set(MEASUREMENT_NAMES).difference(request.measurements):
        return "missing_required_measurement"
    for metric in MEASUREMENT_NAMES:
        value = request.measurements[metric]
        if (
            isinstance(value, bool)
            or not isinstance(value, (int, float))
            or not math.isfinite(float(value))
        ):
            return "non_finite_measurement"

    if request.safety.low_confidence_metrics:
        return "low_confidence_measurement"

    if not isinstance(profile.metrics, Mapping):
        return "invalid_genre_profile"
    if set(MEASUREMENT_NAMES).difference(profile.metrics):
        return "missing_required_profile_metric"
    if (
        isinstance(profile.sample_count, bool)
        or not isinstance(profile.sample_count, int)
        or profile.sample_count < 5
    ):
        return "invalid_genre_profile"
    if profile.corpus_status not in INSTRUMENTAL_STATUSES:
        return "invalid_genre_profile"
    if any(not _valid_target(profile.metrics[name]) for name in MEASUREMENT_NAMES):
        return "invalid_genre_profile"
    return None


def _distance_to_interval(measurement: float, target: MetricTarget) -> tuple[float, str]:
    if measurement < target.lower:
        return target.lower - measurement, "below_genre_range"
    if measurement > target.upper:
        return target.upper - measurement, "above_genre_range"
    return 0.0, "within_genre_range"


def _confidence(
    *,
    knob: str,
    normalized_error: float,
    request: RecommendationRequest,
    profile: GenreProfile,
) -> str:
    score = _CONFIDENCE_SCORE["high"]
    if profile.sample_count < 20:
        score -= 1
    if profile.corpus_status != "confirmed_instrumental":
        score -= 1
    if not request.hardware_response_characterized:
        score -= 1
    if knob in CROSS_COUPLED_KNOBS:
        score -= 1
    if abs(normalized_error) >= 0.75:
        score -= 1
    if (
        request.safety.clipping
        or request.safety.excessive_noise
        or request.safety.excessive_distortion
    ):
        score -= 1
    if request.verification and not (
        request.safety.clipping
        or request.safety.excessive_noise
        or request.safety.excessive_distortion
    ):
        score += 1
    return _SCORE_CONFIDENCE[int(_clamp(float(score), 0.0, 2.0))]


def _bounded_physical_target(
    *,
    request: RecommendationRequest,
    current: float,
    current_normalized: float,
    target_normalized: float,
    cap: float,
) -> float:
    """Choose the nearest supported position without crossing the delta cap."""

    if math.isclose(target_normalized, current_normalized, abs_tol=1e-12):
        return current

    if target_normalized > current_normalized:
        allowed_low = current_normalized
        allowed_high = min(100.0, current_normalized + cap)
    else:
        allowed_low = max(0.0, current_normalized - cap)
        allowed_high = current_normalized

    scale = request.scale
    span = scale.maximum - scale.minimum
    physical_low = scale.minimum + allowed_low * span / 100.0
    physical_high = scale.minimum + allowed_high * span / 100.0
    desired = scale.minimum + target_normalized * span / 100.0

    first_step = math.ceil((physical_low - scale.minimum) / scale.step - 1e-12)
    last_step = math.floor((physical_high - scale.minimum) / scale.step + 1e-12)
    candidates = {current}
    if first_step <= last_step:
        ideal_step = round((desired - scale.minimum) / scale.step)
        for step_index in (
            first_step,
            last_step,
            min(last_step, max(first_step, ideal_step)),
        ):
            candidates.add(
                round(scale.minimum + step_index * scale.step, 12)
            )
    for boundary in (scale.minimum, scale.maximum):
        if physical_low - 1e-12 <= boundary <= physical_high + 1e-12:
            candidates.add(boundary)

    valid_candidates = []
    for candidate in candidates:
        candidate_normalized = scale.normalize(candidate)
        delta = candidate_normalized - current_normalized
        if allowed_low - 1e-9 <= candidate_normalized <= allowed_high + 1e-9:
            valid_candidates.append((candidate, delta))

    recommended, _ = min(
        valid_candidates,
        key=lambda item: (
            abs(scale.normalize(item[0]) - target_normalized),
            abs(item[1]),
        ),
    )
    return recommended


def _adjustment(
    knob: str,
    request: RecommendationRequest,
    profile: GenreProfile,
) -> KnobAdjustment:
    metric = KNOB_TO_METRIC[knob]
    target = profile.metrics[metric]
    measurement = float(request.measurements[metric])
    distance, reason_code = _distance_to_interval(measurement, target)
    normalized_error = _clamp(distance / target.robust_scale, -1.0, 1.0)
    cap = VERIFICATION_DELTA_CAP if request.verification else INITIAL_DELTA_CAP
    raw_delta = MONOTONIC_DIRECTION[knob] * SENSITIVITY_NORMALIZED * normalized_error
    bounded_delta = _clamp(raw_delta, -cap, cap)

    current = getattr(request.current, knob)
    current_normalized = request.scale.normalize(current)
    target_normalized = _clamp(current_normalized + bounded_delta, 0.0, 100.0)

    if knob == "volume" and bounded_delta > 0:
        if request.safety.clipping:
            target_normalized = current_normalized
            reason_code = "volume_increase_blocked_by_clipping"
        elif request.safety.excessive_distortion:
            target_normalized = current_normalized
            reason_code = "volume_increase_blocked_by_distortion"

    recommended = _bounded_physical_target(
        request=request,
        current=current,
        current_normalized=current_normalized,
        target_normalized=target_normalized,
        cap=cap,
    )
    actual_delta_normalized = round(
        request.scale.normalize(recommended) - current_normalized,
        12,
    )
    physical_delta = round(recommended - current, 12)
    confidence = _confidence(
        knob=knob,
        normalized_error=normalized_error,
        request=request,
        profile=profile,
    )
    return KnobAdjustment(
        current=current,
        recommended=recommended,
        delta=physical_delta,
        delta_normalized=actual_delta_normalized,
        reason_code=reason_code,
        confidence=confidence,
    )


def generate_recommendation(
    request: RecommendationRequest,
    profile: GenreProfile,
) -> SettingsRecommendation:
    """Generate deterministic, bounded targets for all five amplifier knobs."""

    if not isinstance(request, RecommendationRequest):
        raise ValueError("request must be a RecommendationRequest")
    if not isinstance(profile, GenreProfile):
        raise ValueError("profile must be a GenreProfile")

    unavailable_reason = _preflight_reason(request, profile)
    if unavailable_reason:
        return _unavailable(request, profile, unavailable_reason)

    adjustments = {
        knob: _adjustment(knob, request, profile) for knob in KNOB_NAMES
    }
    overall_confidence = min(
        (adjustment.confidence for adjustment in adjustments.values()),
        key=_CONFIDENCE_SCORE.__getitem__,
    )
    return SettingsRecommendation(
        status="generated",
        genre=profile.key,
        profile_version=request.profile_version,
        profile_checksum=request.profile_checksum,
        algorithm_version=ALGORITHM_VERSION,
        scale=request.scale,
        current=request.current,
        adjustments=adjustments,
        overall_confidence=overall_confidence,
    )
