"""Public contract for pure amplifier settings recommendations."""

from .engine import ALGORITHM_VERSION, generate_recommendation
from .models import (
    AmplifierScale,
    KnobAdjustment,
    KnobSettings,
    RecommendationRequest,
    SafetySignals,
    SettingsRecommendation,
)

__all__ = [
    "ALGORITHM_VERSION",
    "AmplifierScale",
    "KnobAdjustment",
    "KnobSettings",
    "RecommendationRequest",
    "SafetySignals",
    "SettingsRecommendation",
    "generate_recommendation",
]
