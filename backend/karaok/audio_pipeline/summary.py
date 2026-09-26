"""Summary implementation."""

from __future__ import annotations

from karaok.core.quality import _empirical_result_status
from karaok.core.quality import _score_empirical_values
from karaok.core.values import _nested_number
from typing import Any


def _empirical_feature_values(analysis: dict[str, Any]) -> dict[str, float | None]:
    """Map analyzer output to the five features used by the 30-file reference."""
    return {
        "loudness": _nested_number(analysis, "loudness", "integrated_lufs"),
        "bass": _nested_number(analysis, "bass", "energy_percentage"),
        "treble": _nested_number(analysis, "treble", "energy_percentage"),
        "sharpness": _nested_number(analysis, "sharpness", "normalized_score"),
        "flatness": _nested_number(analysis, "flatness", "mean"),
    }


def _score_analyzer_output(analysis: dict[str, Any]) -> dict[str, Any]:
    empirical, _ = _score_empirical_values(_empirical_feature_values(analysis))
    return empirical


def _analysis_safety_signals(analysis: dict[str, Any]) -> dict[str, Any]:
    quality = analysis.get("quality_assessment")
    quality = quality if isinstance(quality, dict) else {}
    measured = quality.get("measured")
    measured = measured if isinstance(measured, dict) else {}
    thresholds = quality.get("thresholds")
    thresholds = thresholds if isinstance(thresholds, dict) else {}

    clipped = _nested_number(analysis, "distortion", "clipped_sample_percentage")
    clipping_limit = _nested_number(
        thresholds,
        "clipped_samples_failure_above_percentage",
    )
    distortion = _nested_number(analysis, "distortion", "estimated_score")
    distortion_limit = _nested_number(thresholds, "distortion_warning_above")
    snr = _nested_number(measured, "estimated_snr_db")
    noise_limit = _nested_number(thresholds, "snr_warning_below_db")
    return {
        "silent": False,
        "corrupt": False,
        "too_short": False,
        "clipping": (
            clipped is not None
            and clipping_limit is not None
            and clipped > clipping_limit
        ),
        "excessive_noise": (
            snr is not None and noise_limit is not None and snr < noise_limit
        ),
        "excessive_distortion": (
            distortion is not None
            and distortion_limit is not None
            and distortion > distortion_limit
        ),
        "low_confidence_metrics": [],
    }


def summarize_audio_analysis(dump: dict[str, Any]) -> dict[str, Any]:
    """Convert transient analyzer output into the public measured result."""
    analysis = dump.get("analysis")
    if not isinstance(analysis, dict):
        raise RuntimeError("Analyzer output is missing")
    empirical = dump.get("empirical_quality")
    if not isinstance(empirical, dict):
        empirical = _score_analyzer_output(analysis)
        dump["empirical_quality"] = empirical
    quality_score = _nested_number(empirical, "overall_score")
    if quality_score is None:
        raise RuntimeError("Empirical audio score is unavailable")
    result_status = _empirical_result_status(empirical)
    noise_level = _nested_number(analysis, "noise", "noise_dbfs")
    distortion_level = _nested_number(analysis, "distortion", "estimated_score")
    bass = _nested_number(analysis, "bass", "energy_percentage")
    treble = _nested_number(analysis, "treble", "energy_percentage")
    loudness = _nested_number(analysis, "loudness", "integrated_lufs")
    if loudness is None:
        loudness = _nested_number(analysis, "loudness", "mean_dbfs")
    sharpness = _nested_number(analysis, "sharpness", "normalized_score")
    flatness = _nested_number(analysis, "flatness", "mean")
    return {
        "score": quality_score,
        "status": result_status,
        "noise_level": noise_level,
        "distortion_level": distortion_level,
        "bass": bass,
        "treble": treble,
        "loudness": loudness,
        "sharpness": sharpness,
        "flatness": flatness,
        "empirical_quality": empirical,
        "safety_signals": _analysis_safety_signals(analysis),
    }
