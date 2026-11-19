"""Measure production analyzer drift against a clean reference."""

import math
from dataclasses import replace
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any

import numpy as np
import soundfile as sf

from audio_engine.analyzer import _analyze_with_context, evaluate_quality, load_settings
from karaok.audio_pipeline.summary import _empirical_feature_values, summarize_audio_analysis


TOLERANCES = {"score": 5.0, "loudness": 1.0, "bass": 3.0, "ratio_db": 1.0, "ratio_floor": 1e-5}


def analyze_samples(audio, sr, *, preroll=0.0, guard=True):
    with NamedTemporaryFile(suffix=".wav", delete=False) as temp:
        path = Path(temp.name)
    try:
        sf.write(path, audio, sr, subtype="FLOAT")
        settings = load_settings()
        config = replace(settings.noise_guard, enabled=False) if not guard else settings.noise_guard
        analysis, _ = _analyze_with_context(path, settings.analysis, settings.safety, preroll, config)
        analysis["quality_assessment"] = evaluate_quality(analysis, settings.quality_thresholds, config)
        return analysis
    finally:
        path.unlink(missing_ok=True)


def compare(clean: dict, noisy: dict) -> dict[str, Any]:
    clean_summary, noisy_summary = [
        summarize_audio_analysis({"analysis": analysis}) for analysis in (clean, noisy)
    ]
    clean_values, noisy_values = [_empirical_feature_values(a) for a in (clean, noisy)]
    clean_values["score"] = clean_summary["score"]
    noisy_values["score"] = noisy_summary["score"]
    metrics = {}
    for name, reference in clean_values.items():
        measured = noisy_values[name]
        delta = None
        ratio = name in ("treble", "sharpness", "flatness")
        if all(x is not None and math.isfinite(x) for x in (reference, measured)):
            if ratio:
                floor = TOLERANCES["ratio_floor"]
                delta = 10 * math.log10(max(measured, floor) / max(reference, floor))
            else:
                delta = measured - reference
        limit = TOLERANCES["ratio_db" if ratio else name]
        metrics[name] = {"delta": delta, "ok": delta is not None and abs(delta) <= limit}
        if name == "flatness" and noisy.get("flatness", {}).get("reliable") is False:
            metrics[name].update(ok=None, skipped=True)
    status = {"clean": clean_summary["status"], "noisy": noisy_summary["status"]}
    status["ok"] = status["clean"] == status["noisy"]
    return {"metrics": metrics, "status": status,
            "passed": status["ok"] and all(metric["ok"] or metric.get("skipped", False)
                                             for metric in metrics.values())}


def run_case(clean_audio, noise_audio, sr, mnr_db, guard: bool) -> dict:
    preroll = 3 * sr
    length = min(len(clean_audio), len(noise_audio) - preroll)
    if length <= 0:
        raise ValueError("A case requires song samples and noise beyond the 3-second pre-roll.")
    clean = clean_audio[:length]
    noise = noise_audio[preroll:preroll + length]
    noise_norm = np.linalg.norm(noise)
    if not noise_norm:
        raise ValueError("Mix noise must contain nonzero samples.")
    gain = np.linalg.norm(clean) / noise_norm * 10 ** (-mnr_db / 20)
    recording = np.concatenate((noise_audio[:preroll] * gain, clean + noise * gain))
    peak = float(np.max(np.abs(recording)))
    if peak > 1.0:
        raise ValueError(f"Mixture peaks at {peak:.2f} and the analyzer would rescale it; lower the clean level.")
    return analyze_samples(recording, sr, preroll=3.0, guard=guard)

