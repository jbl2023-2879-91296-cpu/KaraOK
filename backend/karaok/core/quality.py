"""Quality implementation."""

from __future__ import annotations

from karaok.core.thresholds import evaluate_features
from karaok.core.thresholds import load_thresholds
from typing import Any


EMPIRICAL_RESULT_STATUSES = {
    "good": "Acceptable",
    "good_but_needs_improvement": "Needs Improvement",
    "bad": "Problematic",
}


RESULT_EMPIRICAL_STATUSES = {
    result_status: empirical_status
    for empirical_status, result_status in EMPIRICAL_RESULT_STATUSES.items()
}


def _score_empirical_values(
    values: dict[str, float | None],
) -> tuple[dict[str, Any], dict[str, Any]]:
    thresholds = load_thresholds()
    empirical = evaluate_features(values, thresholds)
    if empirical.get("overall_score") is None:
        reason = empirical.get("reason", "Empirical audio score is unavailable")
        raise ValueError(str(reason))
    empirical["method"] = "weighted_empirical_good_audio_reference"
    cohort = thresholds.get("cohort")
    empirical["reference_recording_count"] = (
        cohort.get("selected_recording_count") if isinstance(cohort, dict) else None
    )
    empirical["algorithm_version"] = thresholds.get("algorithm_version")
    empirical["quality_profile_version"] = thresholds["quality_profile_version"]
    empirical["quality_profile_checksum"] = thresholds["artifact_checksum"]
    source = thresholds.get("source")
    metrics = thresholds.get("metrics")
    empirical["reference"] = {
        "source_sha256": source.get("sha256") if isinstance(source, dict) else None,
        "classification": thresholds.get("classification"),
        "scoring": thresholds.get("scoring"),
        "overall": thresholds.get("overall"),
        "metrics": metrics,
    }
    return empirical, thresholds


def _empirical_result_status(empirical: dict[str, Any]) -> str:
    status = empirical.get("overall_status")
    try:
        return EMPIRICAL_RESULT_STATUSES[str(status)]
    except KeyError as error:
        raise ValueError(f"Unsupported empirical quality status: {status!r}") from error
