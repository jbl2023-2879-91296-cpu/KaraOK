"""Presentation implementation."""

from __future__ import annotations

from karaok.core.quality import EMPIRICAL_RESULT_STATUSES
from karaok.core.quality import RESULT_EMPIRICAL_STATUSES
from karaok.core.quality import _empirical_result_status
from karaok.core.quality import _score_empirical_values
from karaok.core.runtime import app
from karaok.core.values import _nested_number
from karaok.core import recommendation_contracts as settings_recommendation_service
from typing import Any
import json
import math


def _finite_stored_number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    return number if math.isfinite(number) else None


def _decoded_object(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return dict(value)
    if not isinstance(value, str):
        return {}
    try:
        decoded = json.loads(value)
    except json.JSONDecodeError:
        return {}
    return dict(decoded) if isinstance(decoded, dict) else {}


def _decoded_string_list(value: Any) -> list[str] | None:
    decoded = value
    if isinstance(value, str):
        try:
            decoded = json.loads(value)
        except json.JSONDecodeError:
            return None
    if not isinstance(decoded, list) or any(
        not isinstance(item, str) for item in decoded
    ):
        return None
    return list(decoded)


def _valid_detail_provenance(row_field: str, value: Any) -> Any | None:
    if row_field in {"scoring_algorithm_version", "quality_profile_version"}:
        if isinstance(value, str) and value.strip() and len(value) <= 30:
            return value
        return None
    if row_field == "quality_profile_checksum":
        if (
            isinstance(value, str)
            and len(value) == 64
            and all(character in "0123456789abcdefABCDEF" for character in value)
        ):
            return value
        return None
    if row_field == "reference_recording_count":
        if isinstance(value, int) and not isinstance(value, bool) and value >= 0:
            return value
        return None
    raise ValueError(f"Unsupported provenance field: {row_field}")


def _stored_empirical_result(row: dict[str, Any]) -> dict[str, Any]:
    """Reconstruct one historical empirical snapshot from typed DB fields."""

    empirical = _decoded_object(row.get("empirical_details"))
    stored_score = _finite_stored_number(row.get("score"))
    if stored_score is not None:
        empirical["overall_score"] = stored_score
    else:
        detail_score = _nested_number(empirical, "overall_score")
        if detail_score is not None:
            row["score"] = detail_score

    fallback_status = RESULT_EMPIRICAL_STATUSES.get(str(row.get("status")))
    detail_status = empirical.get("overall_status")
    if detail_status not in EMPIRICAL_RESULT_STATUSES:
        detail_status = None
    stored_status = row.get("empirical_status")
    if stored_status is not None and stored_status not in EMPIRICAL_RESULT_STATUSES:
        app.logger.warning(
            "Stored assessment has unsupported empirical_status %r; "
            "falling back to result_status %r",
            stored_status,
            row.get("status"),
        )
        resolved_status = fallback_status
    else:
        resolved_status = stored_status or detail_status or fallback_status
        if stored_status in EMPIRICAL_RESULT_STATUSES:
            row["status"] = EMPIRICAL_RESULT_STATUSES[stored_status]
    if resolved_status is not None:
        empirical["overall_status"] = resolved_status
        row["empirical_status"] = resolved_status
        row["status"] = EMPIRICAL_RESULT_STATUSES[resolved_status]
    else:
        empirical.pop("overall_status", None)

    detail_worst_status = empirical.get("worst_feature_status")
    if detail_worst_status not in EMPIRICAL_RESULT_STATUSES:
        detail_worst_status = None
    stored_worst_status = row.get("worst_feature_status")
    if stored_worst_status in EMPIRICAL_RESULT_STATUSES:
        resolved_worst_status = stored_worst_status
    else:
        resolved_worst_status = detail_worst_status or resolved_status
    if resolved_worst_status is not None:
        empirical["worst_feature_status"] = resolved_worst_status
    else:
        empirical.pop("worst_feature_status", None)

    detail_worst_features = _decoded_string_list(empirical.get("worst_features"))
    stored_worst_features = _decoded_string_list(row.get("worst_features"))
    empirical["worst_features"] = (
        stored_worst_features
        if stored_worst_features is not None
        else detail_worst_features or []
    )

    for row_field, empirical_field in (
        ("scoring_algorithm_version", "algorithm_version"),
        ("quality_profile_version", "quality_profile_version"),
        ("quality_profile_checksum", "quality_profile_checksum"),
        ("reference_recording_count", "reference_recording_count"),
    ):
        value = row.get(row_field)
        if value is None:
            value = _valid_detail_provenance(
                row_field,
                empirical.get(empirical_field),
            )
            if value is not None:
                row[row_field] = value
        if value is not None:
            empirical[empirical_field] = value
        else:
            empirical.pop(empirical_field, None)
    empirical.setdefault("method", "stored_assessment_snapshot")
    return empirical


def _enrich_audio_test_row(row: dict[str, Any]) -> dict[str, Any]:
    """Attach reproducible empirical details and backfill legacy null scores."""
    stored_empirical_fields = (
        "empirical_status",
        "worst_feature_status",
        "worst_features",
        "empirical_details",
    )
    values = {
        key: row.get(key)
        for key in ("loudness", "bass", "treble", "sharpness", "flatness")
    }
    provenance_fields = (
        "scoring_algorithm_version",
        "quality_profile_version",
        "quality_profile_checksum",
        "reference_recording_count",
    )
    has_stored_history = (
        row.get("score") is not None
        or any(row.get(field) is not None for field in stored_empirical_fields)
        or any(row.get(field) is not None for field in provenance_fields)
    )
    is_legacy_backfill = (
        not has_stored_history
        and all(_finite_stored_number(value) is not None for value in values.values())
    )
    if is_legacy_backfill:
        empirical, thresholds = _score_empirical_values(values)
        row["score"] = empirical["overall_score"]
        row["status"] = _empirical_result_status(empirical)
        row["scoring_algorithm_version"] = thresholds["algorithm_version"]
        row["quality_profile_version"] = thresholds["quality_profile_version"]
        row["quality_profile_checksum"] = thresholds["artifact_checksum"]
        cohort = thresholds.get("cohort")
        row["reference_recording_count"] = (
            cohort.get("selected_recording_count")
            if isinstance(cohort, dict)
            else None
        )
    else:
        empirical = _stored_empirical_result(row)
    row["empirical_quality"] = empirical
    return row


def _attach_stored_recommendation(row: dict[str, Any]) -> dict[str, Any]:
    recommendation = settings_recommendation_service.stored_recommendation_payload(
        row
    )
    for key in tuple(row):
        if key.startswith("settings_") or key in {
            "empirical_status",
            "worst_feature_status",
            "worst_features",
            "empirical_details",
        }:
            row.pop(key)
    if row.get("analysis_purpose") == "settings_suggestion":
        row["settings_recommendation"] = recommendation
    return row
