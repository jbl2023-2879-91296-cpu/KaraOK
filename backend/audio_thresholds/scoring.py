"""Classify and score audio features with a generated threshold artifact."""

from __future__ import annotations

import json
import math
import re
from pathlib import Path
from typing import Any, Mapping

from .artifact_integrity import canonical_artifact_checksum
from .metric_definitions import METRIC_DEFINITIONS, validate_weights

GOOD = "good"
GOOD_BUT_NEEDS_IMPROVEMENT = "good_but_needs_improvement"
BAD = "bad"
NOT_EVALUATED = "not_evaluated"

DEFAULT_THRESHOLD_PATH = Path(__file__).with_name("good_audio_thresholds.json")
_STATUS_SEVERITY = {GOOD: 0, GOOD_BUT_NEEDS_IMPROVEMENT: 1, BAD: 2}
_METRIC_KEYS = tuple(definition.key for definition in METRIC_DEFINITIONS)
_ARTIFACT_KEYS = frozenset(
    {
        "schema_version",
        "quality_profile_version",
        "algorithm_version",
        "purpose",
        "source",
        "cohort",
        "derivation",
        "classification",
        "scoring",
        "overall",
        "metrics",
        "spearman_correlations",
        "recovery_sensitivity",
        "limitations",
        "artifact_checksum",
    }
)
_COHORT_KEYS = frozenset(
    {
        "source_row_count",
        "candidate_completed_count",
        "selected_recording_count",
        "cohort_path_fragment",
        "deduplication_key",
        "deduplication_rule",
        "exclusions",
        "quality_status_counts",
        "decode_status_counts",
        "recovered_frame_percentage_min",
        "recovered_frame_percentage_max",
        "analysis_ids",
        "recording_files",
        "latest_analyzed_at_utc",
    }
)
_EXCLUSION_KEYS = frozenset(
    {
        "not_completed",
        "outside_cohort",
        "duplicate_older_run",
        "invalid_or_non_finite_measurement",
    }
)
_DERIVATION_KEYS = frozenset(
    {
        "library",
        "quantile_method",
        "bootstrap_iterations",
        "bootstrap_seed",
        "bootstrap_confidence_level",
    }
)
_CLASSIFICATION_RULES = {
    "good": "P05 <= value <= P95",
    "good_but_needs_improvement": (
        "observed_min <= value < P05 or P95 < value <= observed_max"
    ),
    "bad": "value < observed_min or value > observed_max",
    "not_evaluated": "value is missing or non-finite",
    "boundary_policy": (
        "All percentile and observed-envelope boundaries are inclusive."
    ),
}
_SCORING_KEYS = frozenset({"range", "anchors", "interpolation"})
_SCORING_ANCHORS = {
    "median": 100.0,
    "p05_and_p95": 80.0,
    "observed_min_and_max": 50.0,
}
_OVERALL_KEYS = frozenset(
    {
        "weights",
        "ranked_features",
        "formula",
        "requires_all_features",
        "status_rules",
        "worst_feature_policy",
        "weight_rationale",
    }
)
_OVERALL_STATUS_RULES = {
    "good": "overall_score >= 80",
    "good_but_needs_improvement": "50 <= overall_score < 80",
    "bad": "overall_score < 50",
    "not_evaluated": "one or more required features are missing or non-finite",
}
_METRIC_SCHEMA_KEYS = frozenset(
    {
        "csv_column",
        "unit",
        "rank",
        "description",
        "sample_count",
        "observed_min",
        "p05",
        "q1",
        "median",
        "q3",
        "p95",
        "observed_max",
        "mean",
        "population_standard_deviation",
        "mad",
        "iqr",
        "bootstrap_95_ci",
    }
)
_BOOTSTRAP_KEYS = frozenset({"p05", "median", "p95"})
_RECOVERY_KEYS = frozenset(
    {"strict_rule", "strict_sample_count", "excluded_from_sensitivity_only", "metrics"}
)
_RECOVERY_METRIC_KEYS = frozenset(
    {
        "strict_p05",
        "strict_median",
        "strict_p95",
        "p05_delta_from_full",
        "median_delta_from_full",
        "p95_delta_from_full",
    }
)


def _exact_mapping(value: Any, keys: frozenset[str] | set[str], field: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or set(value) != set(keys):
        raise ValueError(f"{field} fields do not match the empirical-threshold schema.")
    return value


def _required_string(data: Mapping[str, Any], name: str, field: str) -> str:
    value = data.get(name)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field}.{name} must be a non-empty string.")
    return value


def _strict_finite(value: Any, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{field} must be a finite number.")
    number = float(value)
    if not math.isfinite(number):
        raise ValueError(f"{field} must be a finite number.")
    return number


def _strict_integer(value: Any, field: str, *, minimum: int = 0) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise ValueError(f"{field} must be an integer of at least {minimum}.")
    return value


def _string_list(value: Any, field: str, *, expected_length: int | None = None) -> list[str]:
    if not isinstance(value, list) or any(
        not isinstance(item, str) or not item.strip() for item in value
    ):
        raise ValueError(f"{field} must contain non-empty strings.")
    if expected_length is not None and len(value) != expected_length:
        raise ValueError(f"{field} must contain {expected_length} entries.")
    return value


def _count_mapping(value: Any, field: str, *, expected_total: int) -> None:
    if not isinstance(value, Mapping) or not value:
        raise ValueError(f"{field} must be a non-empty count object.")
    total = 0
    for key, count in value.items():
        if not isinstance(key, str) or not key.strip():
            raise ValueError(f"{field} keys must be non-empty strings.")
        total += _strict_integer(count, f"{field}.{key}")
    if total != expected_total:
        raise ValueError(f"{field} counts must total selected_recording_count.")


def _validate_empirical_artifact(artifact: Mapping[str, Any]) -> None:
    source = _exact_mapping(artifact["source"], {"path", "sha256"}, "source")
    _required_string(source, "path", "source")
    source_checksum = _required_string(source, "sha256", "source")
    if re.fullmatch(r"[0-9a-f]{64}", source_checksum) is None:
        raise ValueError("source.sha256 must be a lowercase SHA-256 checksum.")

    cohort = _exact_mapping(artifact["cohort"], _COHORT_KEYS, "cohort")
    source_count = _strict_integer(cohort["source_row_count"], "cohort.source_row_count")
    candidate_count = _strict_integer(
        cohort["candidate_completed_count"], "cohort.candidate_completed_count"
    )
    selected_count = _strict_integer(
        cohort["selected_recording_count"],
        "cohort.selected_recording_count",
        minimum=1,
    )
    for name in (
        "cohort_path_fragment",
        "deduplication_key",
        "deduplication_rule",
        "latest_analyzed_at_utc",
    ):
        _required_string(cohort, name, "cohort")
    exclusions = _exact_mapping(cohort["exclusions"], _EXCLUSION_KEYS, "cohort.exclusions")
    parsed_exclusions = {
        key: _strict_integer(value, f"cohort.exclusions.{key}")
        for key, value in exclusions.items()
    }
    if source_count != (
        candidate_count
        + parsed_exclusions["not_completed"]
        + parsed_exclusions["outside_cohort"]
    ):
        raise ValueError("cohort source and completion counts are inconsistent.")
    if candidate_count != (
        selected_count
        + parsed_exclusions["duplicate_older_run"]
        + parsed_exclusions["invalid_or_non_finite_measurement"]
    ):
        raise ValueError("cohort selection and exclusion counts are inconsistent.")
    _count_mapping(
        cohort["quality_status_counts"],
        "cohort.quality_status_counts",
        expected_total=selected_count,
    )
    _count_mapping(
        cohort["decode_status_counts"],
        "cohort.decode_status_counts",
        expected_total=selected_count,
    )
    recovered_min = _strict_finite(
        cohort["recovered_frame_percentage_min"],
        "cohort.recovered_frame_percentage_min",
    )
    recovered_max = _strict_finite(
        cohort["recovered_frame_percentage_max"],
        "cohort.recovered_frame_percentage_max",
    )
    if not 0.0 <= recovered_min <= recovered_max <= 100.0:
        raise ValueError("cohort recovered-frame percentages must be ordered within 0-100.")
    analysis_ids = _string_list(
        cohort["analysis_ids"], "cohort.analysis_ids", expected_length=selected_count
    )
    recording_files = _string_list(
        cohort["recording_files"],
        "cohort.recording_files",
        expected_length=selected_count,
    )
    if len(set(analysis_ids)) != selected_count or len(set(recording_files)) != selected_count:
        raise ValueError("cohort analysis and recording evidence must be unique.")

    derivation = _exact_mapping(artifact["derivation"], _DERIVATION_KEYS, "derivation")
    if _required_string(derivation, "library", "derivation") != "NumPy":
        raise ValueError("derivation.library must be NumPy.")
    if _required_string(derivation, "quantile_method", "derivation") != "linear":
        raise ValueError("derivation.quantile_method must be linear.")
    _strict_integer(
        derivation["bootstrap_iterations"],
        "derivation.bootstrap_iterations",
        minimum=100,
    )
    _strict_integer(derivation["bootstrap_seed"], "derivation.bootstrap_seed")
    if _strict_finite(
        derivation["bootstrap_confidence_level"],
        "derivation.bootstrap_confidence_level",
    ) != 0.95:
        raise ValueError("derivation.bootstrap_confidence_level must match bootstrap_95_ci.")

    classification = _exact_mapping(
        artifact["classification"], frozenset(_CLASSIFICATION_RULES), "classification"
    )
    if dict(classification) != _CLASSIFICATION_RULES:
        raise ValueError("classification rules do not match the scoring algorithm.")

    scoring = _exact_mapping(artifact["scoring"], _SCORING_KEYS, "scoring")
    score_range = scoring["range"]
    if (
        not isinstance(score_range, list)
        or len(score_range) != 2
        or [_strict_finite(value, "scoring.range") for value in score_range]
        != [0.0, 100.0]
    ):
        raise ValueError("scoring.range must be exactly 0-100.")
    anchors = _exact_mapping(
        scoring["anchors"], frozenset(_SCORING_ANCHORS), "scoring.anchors"
    )
    parsed_anchors = {
        key: _strict_finite(value, f"scoring.anchors.{key}")
        for key, value in anchors.items()
    }
    if parsed_anchors != _SCORING_ANCHORS:
        raise ValueError("scoring anchors do not match the scoring algorithm.")
    if _required_string(scoring, "interpolation", "scoring") != (
        "directional piecewise linear with scores clamped to 0-100"
    ):
        raise ValueError("scoring.interpolation does not match the scoring algorithm.")

    overall = _exact_mapping(artifact["overall"], _OVERALL_KEYS, "overall")
    weights = _exact_mapping(overall["weights"], set(_METRIC_KEYS), "overall.weights")
    parsed_weights = {
        key: _strict_finite(value, f"overall.weights.{key}")
        for key, value in weights.items()
    }
    validate_weights(parsed_weights)
    if overall["ranked_features"] != list(_METRIC_KEYS):
        raise ValueError("overall.ranked_features must match metric rank order.")
    if _required_string(overall, "formula", "overall") != (
        "sum(feature_score * feature_weight)"
    ):
        raise ValueError("overall.formula does not match the scoring algorithm.")
    if overall["requires_all_features"] is not True:
        raise ValueError("overall.requires_all_features must be true.")
    status_rules = _exact_mapping(
        overall["status_rules"], frozenset(_OVERALL_STATUS_RULES), "overall.status_rules"
    )
    if dict(status_rules) != _OVERALL_STATUS_RULES:
        raise ValueError("overall.status_rules do not match the scoring algorithm.")
    _required_string(overall, "worst_feature_policy", "overall")
    _required_string(overall, "weight_rationale", "overall")

    metrics = _exact_mapping(artifact["metrics"], set(_METRIC_KEYS), "metrics")
    for definition in METRIC_DEFINITIONS:
        field = f"metrics.{definition.key}"
        metric = _exact_mapping(metrics[definition.key], _METRIC_SCHEMA_KEYS, field)
        for name, expected_value in (
            ("csv_column", definition.csv_column),
            ("unit", definition.unit),
            ("description", definition.description),
        ):
            if _required_string(metric, name, field) != expected_value:
                raise ValueError(f"{field}.{name} does not match the metric definition.")
        if (
            _strict_integer(metric["rank"], f"{field}.rank", minimum=1)
            != definition.rank
        ):
            raise ValueError(f"{field}.rank does not match the metric definition.")
        if (
            _strict_integer(
                metric["sample_count"], f"{field}.sample_count", minimum=1
            )
            != selected_count
        ):
            raise ValueError(f"{field}.sample_count does not match the cohort.")
        ordered_names = (
            "observed_min",
            "p05",
            "q1",
            "median",
            "q3",
            "p95",
            "observed_max",
        )
        ordered = [_strict_finite(metric[name], f"{field}.{name}") for name in ordered_names]
        if ordered != sorted(ordered):
            raise ValueError(f"{field} distribution anchors must be ordered.")
        for name in ("mean", "population_standard_deviation", "mad", "iqr"):
            value = _strict_finite(metric[name], f"{field}.{name}")
            if name != "mean" and value < 0.0:
                raise ValueError(f"{field}.{name} must not be negative.")
        bootstrap = _exact_mapping(
            metric["bootstrap_95_ci"], _BOOTSTRAP_KEYS, f"{field}.bootstrap_95_ci"
        )
        for name, interval in bootstrap.items():
            if not isinstance(interval, list) or len(interval) != 2:
                raise ValueError(f"{field}.bootstrap_95_ci.{name} must have two bounds.")
            bounds = [
                _strict_finite(value, f"{field}.bootstrap_95_ci.{name}")
                for value in interval
            ]
            if bounds[0] > bounds[1]:
                raise ValueError(f"{field}.bootstrap_95_ci.{name} must be ordered.")

    correlations = _exact_mapping(
        artifact["spearman_correlations"], set(_METRIC_KEYS), "spearman_correlations"
    )
    parsed_correlations: dict[str, dict[str, float]] = {}
    for row_key, row in correlations.items():
        parsed_row = _exact_mapping(
            row, set(_METRIC_KEYS), f"spearman_correlations.{row_key}"
        )
        parsed_correlations[row_key] = {
            column_key: _strict_finite(
                value, f"spearman_correlations.{row_key}.{column_key}"
            )
            for column_key, value in parsed_row.items()
        }
        if any(abs(value) > 1.0 for value in parsed_correlations[row_key].values()):
            raise ValueError("spearman correlations must be within -1 and 1.")
        if parsed_correlations[row_key][row_key] != 1.0:
            raise ValueError("spearman correlation diagonal values must equal 1.")
    for row_key in _METRIC_KEYS:
        for column_key in _METRIC_KEYS:
            if abs(
                parsed_correlations[row_key][column_key]
                - parsed_correlations[column_key][row_key]
            ) > 1e-12:
                raise ValueError("spearman correlations must be symmetric.")

    recovery = _exact_mapping(
        artifact["recovery_sensitivity"], _RECOVERY_KEYS, "recovery_sensitivity"
    )
    _required_string(recovery, "strict_rule", "recovery_sensitivity")
    strict_count = _strict_integer(
        recovery["strict_sample_count"], "recovery_sensitivity.strict_sample_count"
    )
    excluded_count = _strict_integer(
        recovery["excluded_from_sensitivity_only"],
        "recovery_sensitivity.excluded_from_sensitivity_only",
    )
    if strict_count + excluded_count != selected_count:
        raise ValueError("recovery-sensitivity counts do not match the cohort.")
    recovery_metrics = _exact_mapping(
        recovery["metrics"], set(_METRIC_KEYS), "recovery_sensitivity.metrics"
    )
    for metric_key, raw_metric in recovery_metrics.items():
        field = f"recovery_sensitivity.metrics.{metric_key}"
        metric = _exact_mapping(raw_metric, _RECOVERY_METRIC_KEYS, field)
        parsed = {
            key: _strict_finite(value, f"{field}.{key}")
            for key, value in metric.items()
        }
        if not parsed["strict_p05"] <= parsed["strict_median"] <= parsed["strict_p95"]:
            raise ValueError(f"{field} strict distribution anchors must be ordered.")

    _string_list(artifact["limitations"], "limitations")


def load_thresholds(path: str | Path = DEFAULT_THRESHOLD_PATH) -> dict[str, Any]:
    """Load and validate a generated empirical-threshold JSON file."""

    threshold_path = Path(path)
    try:
        artifact = json.loads(threshold_path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ValueError(f"Threshold file does not exist: {threshold_path}") from error
    except json.JSONDecodeError as error:
        raise ValueError(f"Threshold file is not valid JSON: {error}") from error

    artifact = _exact_mapping(artifact, _ARTIFACT_KEYS, "artifact")
    if (
        isinstance(artifact.get("schema_version"), bool)
        or not isinstance(artifact.get("schema_version"), int)
        or artifact["schema_version"] != 1
    ):
        raise ValueError("Unsupported or missing empirical-threshold schema_version.")
    for field in ("quality_profile_version", "algorithm_version", "artifact_checksum"):
        if not isinstance(artifact.get(field), str) or not artifact[field].strip():
            raise ValueError(f"Threshold file is missing {field}.")
    if re.fullmatch(r"[0-9a-f]{64}", artifact["artifact_checksum"]) is None:
        raise ValueError("Threshold artifact_checksum must be a lowercase SHA-256 checksum.")
    expected = canonical_artifact_checksum(artifact)
    if artifact["artifact_checksum"] != expected:
        raise ValueError("Threshold artifact checksum does not match canonical content.")
    _required_string(artifact, "purpose", "artifact")
    _validate_empirical_artifact(artifact)
    return dict(artifact)


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
