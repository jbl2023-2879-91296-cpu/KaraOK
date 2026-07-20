"""Definitions for the five empirical good-audio features."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class MetricDefinition:
    """CSV location and scoring metadata for one feature."""

    key: str
    csv_column: str
    unit: str
    weight: float
    rank: int
    description: str


METRIC_DEFINITIONS: tuple[MetricDefinition, ...] = (
    MetricDefinition(
        key="loudness",
        csv_column="loudness.integrated_lufs",
        unit="LUFS",
        weight=0.30,
        rank=1,
        description="ITU-R BS.1770-5-aligned integrated mono loudness.",
    ),
    MetricDefinition(
        key="bass",
        csv_column="bass.energy_percentage",
        unit="percent",
        weight=0.25,
        rank=2,
        description="Bass-band share of active-frame spectral energy.",
    ),
    MetricDefinition(
        key="treble",
        csv_column="treble.energy_percentage",
        unit="percent",
        weight=0.20,
        rank=3,
        description="Treble-band share of active-frame spectral energy.",
    ),
    MetricDefinition(
        key="sharpness",
        csv_column="sharpness.normalized_score",
        unit="normalized_score",
        weight=0.15,
        rank=4,
        description="Approximate normalized high-frequency-weighted score; not acum.",
    ),
    MetricDefinition(
        key="flatness",
        csv_column="flatness.mean",
        unit="ratio",
        weight=0.10,
        rank=5,
        description="Mean spectral flatness over active frames.",
    ),
)


def default_weights() -> dict[str, float]:
    """Return a fresh mapping of feature names to default weights."""

    return {definition.key: definition.weight for definition in METRIC_DEFINITIONS}


def validate_weights(weights: dict[str, float]) -> None:
    """Reject missing, non-positive, non-finite, or non-normalized weights."""

    expected = {definition.key for definition in METRIC_DEFINITIONS}
    actual = set(weights)
    if actual != expected:
        missing = sorted(expected - actual)
        unknown = sorted(actual - expected)
        raise ValueError(f"Invalid feature weights; missing={missing}, unknown={unknown}.")

    numeric = [float(weights[key]) for key in sorted(expected)]
    if any(
        value <= 0.0
        or value != value
        or value in (float("inf"), float("-inf"))
        for value in numeric
    ):
        raise ValueError("Every feature weight must be positive and finite.")
    if abs(sum(numeric) - 1.0) > 1e-9:
        raise ValueError(f"Feature weights must sum to 1.0; received {sum(numeric):.12g}.")
