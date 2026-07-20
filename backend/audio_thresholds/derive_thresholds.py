"""Derive reproducible good-audio thresholds from the shared results CSV."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
import ntpath
import os
import tempfile
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Sequence

import numpy as np
from numpy.typing import NDArray

if __package__ in (None, ""):
    import sys

    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from audio_thresholds.metric_definitions import (  # type: ignore[import-not-found]
        METRIC_DEFINITIONS,
        default_weights,
        validate_weights,
    )
else:
    from .metric_definitions import METRIC_DEFINITIONS, default_weights, validate_weights


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE_PATH = REPOSITORY_ROOT / "results" / "results.csv"
DEFAULT_OUTPUT_PATH = Path(__file__).with_name("good_audio_thresholds.json")
DEFAULT_COHORT_FRAGMENT = "audio sample(good)"
DEFAULT_BOOTSTRAP_ITERATIONS = 10_000
DEFAULT_BOOTSTRAP_SEED = 20_260_719
DEFAULT_MINIMUM_SAMPLES = 20
STRICT_RECOVERY_PERCENTAGE = 99.0

BASE_REQUIRED_COLUMNS = {
    "analysis_id",
    "analyzed_at_utc",
    "file_information.file_path",
    "file_information.decode_status",
    "file_information.recovered_frame_percentage",
    "analysis_information.analysis_status",
    "quality_assessment.status",
}


@dataclass(frozen=True)
class CohortData:
    """Validated rows and NumPy arrays selected from the source CSV."""

    rows: tuple[dict[str, str], ...]
    values: dict[str, NDArray[np.float64]]
    source_sha256: str
    summary: dict[str, Any]


def _normalized_path(value: str) -> str:
    return value.strip().replace("\\", "/").lower()


def _finite_float(value: str) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


def _recovery_percentage(row: Mapping[str, str]) -> float:
    value = _finite_float(row.get("file_information.recovered_frame_percentage", ""))
    if value is not None:
        return value
    return 100.0 if row.get("file_information.decode_status", "").strip().lower() == "complete" else 0.0


def load_good_cohort(
    source_path: str | Path = DEFAULT_SOURCE_PATH,
    *,
    cohort_fragment: str = DEFAULT_COHORT_FRAGMENT,
    minimum_samples: int = DEFAULT_MINIMUM_SAMPLES,
) -> CohortData:
    """Load, filter, deduplicate, and validate the known-good recording cohort."""

    path = Path(source_path)
    try:
        source_bytes = path.read_bytes()
    except FileNotFoundError as error:
        raise ValueError(f"Results CSV does not exist: {path}") from error
    source_sha256 = hashlib.sha256(source_bytes).hexdigest()

    text = source_bytes.decode("utf-8-sig")
    reader = csv.DictReader(io.StringIO(text, newline=""))
    headers = set(reader.fieldnames or ())
    required = BASE_REQUIRED_COLUMNS | {
        definition.csv_column for definition in METRIC_DEFINITIONS
    }
    missing = sorted(required - headers)
    if missing:
        raise ValueError(f"Results CSV is missing required columns: {missing}")

    all_rows = [dict(row) for row in reader]
    normalized_fragment = _normalized_path(cohort_fragment)
    completed: list[dict[str, str]] = []
    not_completed = 0
    outside_cohort = 0
    for row in all_rows:
        if row["analysis_information.analysis_status"].strip().lower() != "completed":
            not_completed += 1
            continue
        if normalized_fragment and normalized_fragment not in _normalized_path(
            row["file_information.file_path"]
        ):
            outside_cohort += 1
            continue
        completed.append(row)

    latest_by_path: dict[str, dict[str, str]] = {}
    duplicate_older_run = 0
    for row in sorted(completed, key=lambda item: (item["analyzed_at_utc"], item["analysis_id"])):
        key = _normalized_path(row["file_information.file_path"])
        if key in latest_by_path:
            duplicate_older_run += 1
        latest_by_path[key] = row

    valid_rows: list[dict[str, str]] = []
    invalid_measurement = 0
    for row in latest_by_path.values():
        numbers = [_finite_float(row[definition.csv_column]) for definition in METRIC_DEFINITIONS]
        if any(number is None for number in numbers):
            invalid_measurement += 1
            continue
        valid_rows.append(row)
    valid_rows.sort(key=lambda item: (item["analyzed_at_utc"], item["analysis_id"]))

    if len(valid_rows) < minimum_samples:
        raise ValueError(
            f"The cohort has {len(valid_rows)} valid recordings; at least {minimum_samples} are required."
        )

    values = {
        definition.key: np.asarray(
            [float(row[definition.csv_column]) for row in valid_rows],
            dtype=np.float64,
        )
        for definition in METRIC_DEFINITIONS
    }
    recovery = np.asarray([_recovery_percentage(row) for row in valid_rows], dtype=np.float64)
    summary = {
        "source_row_count": len(all_rows),
        "candidate_completed_count": len(completed),
        "selected_recording_count": len(valid_rows),
        "cohort_path_fragment": cohort_fragment,
        "deduplication_key": "normalized file_information.file_path",
        "deduplication_rule": "latest analyzed_at_utc, then analysis_id",
        "exclusions": {
            "not_completed": not_completed,
            "outside_cohort": outside_cohort,
            "duplicate_older_run": duplicate_older_run,
            "invalid_or_non_finite_measurement": invalid_measurement,
        },
        "quality_status_counts": dict(sorted(Counter(row["quality_assessment.status"] for row in valid_rows).items())),
        "decode_status_counts": dict(sorted(Counter(row["file_information.decode_status"] for row in valid_rows).items())),
        "recovered_frame_percentage_min": float(np.min(recovery)),
        "recovered_frame_percentage_max": float(np.max(recovery)),
        "analysis_ids": [row["analysis_id"] for row in valid_rows],
        "recording_files": [ntpath.basename(row["file_information.file_path"]) for row in valid_rows],
        "latest_analyzed_at_utc": max(row["analyzed_at_utc"] for row in valid_rows),
    }
    return CohortData(tuple(valid_rows), values, source_sha256, summary)


def _bootstrap_intervals(
    values: NDArray[np.float64],
    *,
    iterations: int,
    seed: int,
) -> dict[str, list[float]]:
    if iterations < 100:
        raise ValueError("bootstrap_iterations must be at least 100.")
    random = np.random.default_rng(seed)
    sample_indices = random.integers(0, values.size, size=(iterations, values.size))
    samples = values[sample_indices]
    quantiles = np.quantile(samples, [0.05, 0.50, 0.95], axis=1)
    names = ("p05", "median", "p95")
    return {
        name: [float(number) for number in np.quantile(quantiles[index], [0.025, 0.975])]
        for index, name in enumerate(names)
    }


def _statistics(
    values: NDArray[np.float64],
    *,
    bootstrap_iterations: int,
    bootstrap_seed: int,
) -> dict[str, Any]:
    p05, q1, median, q3, p95 = np.quantile(values, [0.05, 0.25, 0.50, 0.75, 0.95])
    return {
        "sample_count": int(values.size),
        "observed_min": float(np.min(values)),
        "p05": float(p05),
        "q1": float(q1),
        "median": float(median),
        "q3": float(q3),
        "p95": float(p95),
        "observed_max": float(np.max(values)),
        "mean": float(np.mean(values)),
        "population_standard_deviation": float(np.std(values, ddof=0)),
        "mad": float(np.median(np.abs(values - median))),
        "iqr": float(q3 - q1),
        "bootstrap_95_ci": _bootstrap_intervals(
            values,
            iterations=bootstrap_iterations,
            seed=bootstrap_seed,
        ),
    }


def _average_ranks(values: NDArray[np.float64]) -> NDArray[np.float64]:
    order = np.argsort(values, kind="mergesort")
    sorted_values = values[order]
    ranks = np.empty(values.size, dtype=np.float64)
    start = 0
    while start < values.size:
        end = start + 1
        while end < values.size and sorted_values[end] == sorted_values[start]:
            end += 1
        ranks[order[start:end]] = (start + end - 1) / 2.0 + 1.0
        start = end
    return ranks


def _spearman_correlations(values: dict[str, NDArray[np.float64]]) -> dict[str, dict[str, float]]:
    keys = [definition.key for definition in METRIC_DEFINITIONS]
    ranks = np.column_stack([_average_ranks(values[key]) for key in keys])
    matrix = np.corrcoef(ranks, rowvar=False)
    return {
        row_key: {column_key: float(matrix[row_index, column_index]) for column_index, column_key in enumerate(keys)}
        for row_index, row_key in enumerate(keys)
    }


def _recovery_sensitivity(
    cohort: CohortData,
    full_statistics: Mapping[str, Mapping[str, Any]],
) -> dict[str, Any]:
    mask = np.asarray(
        [
            row["file_information.decode_status"].strip().lower() == "complete"
            or _recovery_percentage(row) >= STRICT_RECOVERY_PERCENTAGE
            for row in cohort.rows
        ],
        dtype=bool,
    )
    comparisons: dict[str, dict[str, float]] = {}
    for definition in METRIC_DEFINITIONS:
        strict_values = cohort.values[definition.key][mask]
        strict_p05, strict_median, strict_p95 = np.quantile(strict_values, [0.05, 0.50, 0.95])
        full = full_statistics[definition.key]
        comparisons[definition.key] = {
            "strict_p05": float(strict_p05),
            "strict_median": float(strict_median),
            "strict_p95": float(strict_p95),
            "p05_delta_from_full": float(strict_p05 - float(full["p05"])),
            "median_delta_from_full": float(strict_median - float(full["median"])),
            "p95_delta_from_full": float(strict_p95 - float(full["p95"])),
        }
    return {
        "strict_rule": (
            "decode_status is complete or recovered_frame_percentage is at least "
            f"{STRICT_RECOVERY_PERCENTAGE:.1f}"
        ),
        "strict_sample_count": int(np.count_nonzero(mask)),
        "excluded_from_sensitivity_only": int(mask.size - np.count_nonzero(mask)),
        "metrics": comparisons,
    }


def derive_threshold_artifact(
    source_path: str | Path = DEFAULT_SOURCE_PATH,
    *,
    source_label: str | None = None,
    cohort_fragment: str = DEFAULT_COHORT_FRAGMENT,
    minimum_samples: int = DEFAULT_MINIMUM_SAMPLES,
    bootstrap_iterations: int = DEFAULT_BOOTSTRAP_ITERATIONS,
    bootstrap_seed: int = DEFAULT_BOOTSTRAP_SEED,
) -> dict[str, Any]:
    """Build the deterministic JSON-serializable empirical-threshold artifact."""

    cohort = load_good_cohort(
        source_path,
        cohort_fragment=cohort_fragment,
        minimum_samples=minimum_samples,
    )
    weights = default_weights()
    validate_weights(weights)

    metric_statistics: dict[str, dict[str, Any]] = {}
    for index, definition in enumerate(METRIC_DEFINITIONS):
        statistics = _statistics(
            cohort.values[definition.key],
            bootstrap_iterations=bootstrap_iterations,
            bootstrap_seed=bootstrap_seed + index,
        )
        metric_statistics[definition.key] = {
            "csv_column": definition.csv_column,
            "unit": definition.unit,
            "rank": definition.rank,
            "description": definition.description,
            **statistics,
        }

    label = source_label if source_label is not None else Path(source_path).as_posix()
    return {
        "schema_version": 1,
        "algorithm_version": "1.0.0",
        "purpose": "Provisional empirical reference for recordings labeled good.",
        "source": {
            "path": label,
            "sha256": cohort.source_sha256,
        },
        "cohort": cohort.summary,
        "derivation": {
            "library": "NumPy",
            "quantile_method": "linear",
            "bootstrap_iterations": bootstrap_iterations,
            "bootstrap_seed": bootstrap_seed,
            "bootstrap_confidence_level": 0.95,
        },
        "classification": {
            "good": "P05 <= value <= P95",
            "good_but_needs_improvement": (
                "observed_min <= value < P05 or P95 < value <= observed_max"
            ),
            "bad": "value < observed_min or value > observed_max",
            "not_evaluated": "value is missing or non-finite",
            "boundary_policy": "All percentile and observed-envelope boundaries are inclusive.",
        },
        "scoring": {
            "range": [0.0, 100.0],
            "anchors": {
                "median": 100.0,
                "p05_and_p95": 80.0,
                "observed_min_and_max": 50.0,
            },
            "interpolation": "directional piecewise linear with scores clamped to 0-100",
        },
        "overall": {
            "weights": weights,
            "ranked_features": [definition.key for definition in METRIC_DEFINITIONS],
            "formula": "sum(feature_score * feature_weight)",
            "requires_all_features": True,
            "status_rules": {
                "good": "overall_score >= 80",
                "good_but_needs_improvement": "50 <= overall_score < 80",
                "bad": "overall_score < 50",
                "not_evaluated": "one or more required features are missing or non-finite",
            },
            "worst_feature_policy": (
                "Report the most severe feature status and responsible features separately; "
                "do not replace the weighted overall status."
            ),
            "weight_rationale": (
                "Defaults prioritize level and tonal balance while limiting double-counting "
                "among correlated treble, sharpness, and flatness features."
            ),
        },
        "metrics": metric_statistics,
        "spearman_correlations": _spearman_correlations(cohort.values),
        "recovery_sensitivity": _recovery_sensitivity(cohort, metric_statistics),
        "limitations": [
            "The cohort contains only 30 recordings labeled good and has no improvement or bad labels.",
            "Bad means outside this cohort's observed envelope; it is an operational flag, not a validated diagnosis.",
            "The default weights are transparent engineering defaults, not learned perceptual importance weights.",
            "Treble, sharpness, and flatness are correlated and remain dependent on program content.",
            "The cohort is limited to the current phone-recording and analyzer conditions.",
        ],
    }


def write_threshold_artifact(artifact: Mapping[str, Any], output_path: str | Path) -> Path:
    """Atomically write a formatted threshold JSON file."""

    destination = Path(output_path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(artifact, indent=2, sort_keys=False, allow_nan=False) + "\n"
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{destination.name}.", suffix=".tmp", dir=destination.parent
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as target:
            target.write(payload)
        Path(temporary_name).replace(destination)
    except Exception:
        Path(temporary_name).unlink(missing_ok=True)
        raise
    return destination


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Derive empirical good-audio thresholds from results/results.csv using NumPy."
    )
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE_PATH)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    parser.add_argument("--cohort-fragment", default=DEFAULT_COHORT_FRAGMENT)
    parser.add_argument("--minimum-samples", type=int, default=DEFAULT_MINIMUM_SAMPLES)
    parser.add_argument("--bootstrap-iterations", type=int, default=DEFAULT_BOOTSTRAP_ITERATIONS)
    parser.add_argument("--bootstrap-seed", type=int, default=DEFAULT_BOOTSTRAP_SEED)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        artifact = derive_threshold_artifact(
            args.source,
            source_label="results/results.csv" if args.source.resolve() == DEFAULT_SOURCE_PATH.resolve() else None,
            cohort_fragment=args.cohort_fragment,
            minimum_samples=args.minimum_samples,
            bootstrap_iterations=args.bootstrap_iterations,
            bootstrap_seed=args.bootstrap_seed,
        )
        destination = write_threshold_artifact(artifact, args.output)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"Threshold derivation error: {error}")
        return 2

    print(f"Derived thresholds from {artifact['cohort']['selected_recording_count']} recordings.")
    print(f"Source SHA-256: {artifact['source']['sha256']}")
    print(f"Saved: {destination.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
