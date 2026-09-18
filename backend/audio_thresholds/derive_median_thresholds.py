"""Build the versioned assessment profile approved in KaraOK Median.pdf.

Reference distribution statistics stay intact; assessment_bounds carry the
translated cutoffs. The original empirical artifact remains independently usable.
"""
from __future__ import annotations

import copy
from pathlib import Path

from .artifact_integrity import canonical_artifact_checksum
from .derive_thresholds import write_threshold_artifact
from .scoring import load_thresholds, MEDIAN_CLASSIFICATION_RULES, MEDIAN_SCORING_ANCHORS

BASELINE = Path(__file__).with_name("good_audio_thresholds.json")
OUTPUT = Path(__file__).with_name("median_centered_thresholds.json")


def derive_median_profile() -> dict:
    artifact = copy.deepcopy(load_thresholds(BASELINE))
    artifact["schema_version"] = 2
    artifact["quality_profile_version"] = "2026.09.2-median"
    artifact["purpose"] = (
        "Median-centered equal-width assessment profile approved from KaraOK Median.pdf. "
        "Full-precision centers match the prior 26-Good-recording medians. "
        "Loudness width is 2.94 LUFS; other widths are reference P95 minus P05. "
        "Original distribution statistics are preserved separately from assessment_bounds."
    )
    artifact["classification"] = dict(MEDIAN_CLASSIFICATION_RULES)
    artifact["scoring"]["anchors"] = dict(MEDIAN_SCORING_ANCHORS)
    for name, metric in artifact["metrics"].items():
        width = 2.94 if name == "loudness" else metric["p95"] - metric["p05"]
        center = metric["median"]
        metric["assessment_bounds"] = {
            "improvement_lower": center - 1.5 * width,
            "good_lower": center - 0.5 * width,
            "center": center,
            "good_upper": center + 0.5 * width,
            "improvement_upper": center + 1.5 * width,
        }
    artifact["limitations"] = [
        "The profile is a user-selected symmetric hypothesis, not listener-validated class boundaries.",
        "Mathematical bands can extend below zero or above physical limits; they are not physical collection targets.",
        "Centers are fixed from the original cohort and are not recalculated after reclassification.",
        "Bad means outside the configured improvement bounds, not outside the observed cohort envelope.",
        "Feature extraction, weights, and the 80/50 overall grade cutoffs are unchanged.",
    ]
    artifact["artifact_checksum"] = canonical_artifact_checksum(artifact)
    return artifact


if __name__ == "__main__":
    write_threshold_artifact(derive_median_profile(), OUTPUT)
    load_thresholds(OUTPUT)
    print(OUTPUT)
