"""Classify and score audio features with a generated threshold artifact."""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any, Mapping

from .metric_definitions import METRIC_DEFINITIONS, validate_weights

GOOD = "good"
GOOD_BUT_NEEDS_IMPROVEMENT = "good_but_needs_improvement"
BAD = "bad"
NOT_EVALUATED = "not_evaluated"

DEFAULT_THRESHOLD_PATH = Path(__file__).with_name("good_audio_thresholds.json")
_STATUS_SEVERITY = {GOOD: 0, GOOD_BUT_NEEDS_IMPROVEMENT: 1, BAD: 2}


def load_thresholds(path: str | Path = DEFAULT_THRESHOLD_PATH) -> dict[str, Any]:
    """Load and validate a generated empirical-threshold JSON file."""

    threshold_path = Path(path)
    try:
        artifact = json.loads(threshold_path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ValueError(f"Threshold file does not exist: {threshold_path}") from error
    except json.JSONDecodeError as error:
        raise ValueError(f"Threshold file is not valid JSON: {error}") from error

    if artifact.get("schema_version") != 1:
        raise ValueError("Unsupported or missing empirical-threshold schema_version.")
    metrics = artifact.get("metrics")
    if not isinstance(metrics, dict):
        raise ValueError("Threshold file is missing its metrics object.")
    for definition in METRIC_DEFINITIONS:
        if definition.key not in metrics:
            raise ValueError(f"Threshold file is missing metric {definition.key!r}.")
        _validated_bounds(metrics[definition.key])

    overall = artifact.get("overall")
    if not isinstance(overall, dict) or not isinstance(overall.get("weights"), dict):
        raise ValueError("Threshold file is missing overall.weights.")
    validate_weights(overall["weights"])
    return artifact


def _finite_number(value: object) -> float | None:
    if isinstance(value, bool):
        return None
    try:
        number = float(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


def _validated_bounds(metric: Mapping[str, Any]) -> tuple[float, float, float, float, float]:
    names = ("observed_min", "p05", "median", "p95", "observed_max")
    values = tuple(_finite_number(metric.get(name)) for name in names)
    if any(value is None for value in values):
        raise ValueError(f"Metric bounds must be finite numbers: {names}.")
    bounds = tuple(float(value) for value in values if value is not None)
    if list(bounds) != sorted(bounds):
        raise ValueError(f"Metric bounds are not ordered: {bounds}.")
    return bounds  # type: ignore[return-value]


def classify_feature(value: object, metric: Mapping[str, Any]) -> str:
    """Apply the inclusive P05/P95 and observed-envelope status rules."""

    number = _finite_number(value)
    if number is None:
        return NOT_EVALUATED
    observed_min, p05, _, p95, observed_max = _validated_bounds(metric)
    if p05 <= number <= p95:
        return GOOD
    if observed_min <= number <= observed_max:
        return GOOD_BUT_NEEDS_IMPROVEMENT
    return BAD


def _linear_score(
    value: float,
    start_value: float,
    start_score: float,
    end_value: float,
    end_score: float,
) -> float:
    if start_value == end_value:
        return min(start_score, end_score)
    fraction = (value - start_value) / (end_value - start_value)
    return start_score + fraction * (end_score - start_score)


def score_feature(value: object, metric: Mapping[str, Any]) -> float | None:
    """Return a continuous score anchored at median/P05-P95/envelope bounds."""

    number = _finite_number(value)
    if number is None:
        return None
    observed_min, p05, median, p95, observed_max = _validated_bounds(metric)

    if number == median:
        score = 100.0
    elif p05 <= number < median:
        score = _linear_score(number, p05, 80.0, median, 100.0)
    elif median < number <= p95:
        score = _linear_score(number, median, 100.0, p95, 80.0)
    elif observed_min <= number < p05:
        score = _linear_score(number, observed_min, 50.0, p05, 80.0)
    elif p95 < number <= observed_max:
        score = _linear_score(number, p95, 80.0, observed_max, 50.0)
    elif number < observed_min:
        tail_width = max(p05 - observed_min, median - p05, 1e-12)
        score = 50.0 - 50.0 * (observed_min - number) / tail_width
    else:
        tail_width = max(observed_max - p95, p95 - median, 1e-12)
        score = 50.0 - 50.0 * (number - observed_max) / tail_width

    return float(min(100.0, max(0.0, score)))


def _overall_status(score: float) -> str:
    if score >= 80.0:
        return GOOD
    if score >= 50.0:
        return GOOD_BUT_NEEDS_IMPROVEMENT
    return BAD


def evaluate_features(
    values: Mapping[str, object],
    thresholds: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Score all five features and return weighted and worst-feature results."""

    artifact = dict(thresholds) if thresholds is not None else load_thresholds()
    metrics = artifact.get("metrics")
    overall = artifact.get("overall")
    if not isinstance(metrics, Mapping) or not isinstance(overall, Mapping):
        raise ValueError("Threshold data must contain metrics and overall objects.")
    raw_weights = overall.get("weights")
    if not isinstance(raw_weights, dict):
        raise ValueError("Threshold data must contain overall.weights.")
    weights = {key: float(value) for key, value in raw_weights.items()}
    validate_weights(weights)

    feature_results: dict[str, dict[str, Any]] = {}
    invalid_features: list[str] = []
    for definition in METRIC_DEFINITIONS:
        metric = metrics.get(definition.key)
        if not isinstance(metric, Mapping):
            raise ValueError(f"Threshold data is missing metric {definition.key!r}.")
        status = classify_feature(values.get(definition.key), metric)
        score = score_feature(values.get(definition.key), metric)
        if status == NOT_EVALUATED:
            invalid_features.append(definition.key)
        feature_results[definition.key] = {
            "value": _finite_number(values.get(definition.key)),
            "status": status,
            "score": score,
            "weight": weights[definition.key],
            "weighted_points": None if score is None else score * weights[definition.key],
            "rank": definition.rank,
        }

    if invalid_features:
        return {
            "overall_score": None,
            "overall_status": NOT_EVALUATED,
            "worst_feature_status": NOT_EVALUATED,
            "worst_features": invalid_features,
            "features": feature_results,
            "reason": "All five required feature measurements must be finite.",
        }

    overall_score = float(
        sum(float(result["weighted_points"]) for result in feature_results.values())
    )
    worst_severity = max(_STATUS_SEVERITY[result["status"]] for result in feature_results.values())
    worst_status = next(status for status, severity in _STATUS_SEVERITY.items() if severity == worst_severity)
    worst_features = [
        key for key, result in feature_results.items() if result["status"] == worst_status
    ]
    return {
        "overall_score": overall_score,
        "overall_status": _overall_status(overall_score),
        "worst_feature_status": worst_status,
        "worst_features": worst_features,
        "features": feature_results,
    }
