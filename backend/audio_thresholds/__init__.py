"""Empirical good-audio thresholds and scoring helpers."""

from .metric_definitions import METRIC_DEFINITIONS, MetricDefinition
from .genre_profiles import (
    GenreProfileArtifact,
    clear_genre_profile_cache,
    load_genre_profiles,
    normalize_genre,
)
from .control_priors import (
    ControlPriorArtifact,
    clear_control_prior_cache,
    load_control_priors,
)
from .scoring import (
    BAD,
    GOOD,
    GOOD_BUT_NEEDS_IMPROVEMENT,
    NOT_EVALUATED,
    classify_feature,
    evaluate_features,
    load_thresholds,
    score_feature,
)

__all__ = [
    "BAD",
    "GOOD",
    "GOOD_BUT_NEEDS_IMPROVEMENT",
    "METRIC_DEFINITIONS",
    "NOT_EVALUATED",
    "MetricDefinition",
    "GenreProfileArtifact",
    "ControlPriorArtifact",
    "clear_control_prior_cache",
    "clear_genre_profile_cache",
    "classify_feature",
    "evaluate_features",
    "load_thresholds",
    "load_control_priors",
    "load_genre_profiles",
    "normalize_genre",
    "score_feature",
]
