"""Standalone audio feature extraction and quality analysis CLI.

Technical disclaimer
--------------------
* Bass and treble are frequency-band energy measurements.
* Loudness is an RMS-based dBFS approximation, not LUFS.
* Sharpness is an approximate normalized spectral measurement, not a certified
  psychoacoustic sharpness measurement in acum.
* Noise level and SNR are estimated without a separate noise recording.
* Distortion is a no-reference heuristic and is not laboratory-measured THD or
  THD+N. A known test tone, its fundamental, or a clean reference is required
  for a defensible THD measurement.

Example:
    python audio_analyzer.py input_audio.wav --output-dir results
    python audio_analyzer.py song.mp3 --frame-length 4096 --noise-percentile 15
    python audio_analyzer.py song.flac --no-save-plots --save-json --save-csv
"""

# cspell:ignore audioread dBFS librosa libsndfile LUFS nperseg STFT THD

from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import asdict, dataclass, field, replace
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Sequence, cast

import matplotlib
import numpy as np
import pandas as pd
import soundfile as sf
from scipy.signal import welch
from scipy.signal.windows import hann

# Use a non-interactive backend so plots also work on servers and in CI.
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402  (backend must be selected first)
import librosa  # noqa: E402
import librosa.display  # noqa: E402


EPSILON = 1.0e-12
SUPPORTED_EXTENSIONS = {".wav", ".mp3", ".flac", ".ogg"}
RECOVERY_BLOCK_FRAMES = 65_536
DEFAULT_SETTINGS_PATH = Path(__file__).with_name("audio_analyzer_settings.json")


class AudioAnalysisError(ValueError):
    """A clear, user-facing error caused by the input or configuration."""


@contextmanager
def _suppress_native_decoder_diagnostics() -> Iterator[None]:
    """Temporarily silence native codec stderr while errors are handled in Python."""
    try:
        stderr_fd = sys.stderr.fileno()
        saved_fd = os.dup(stderr_fd)
    except (AttributeError, OSError, ValueError):
        yield
        return

    try:
        sys.stderr.flush()
        with open(os.devnull, "w", encoding="utf-8") as sink:
            os.dup2(sink.fileno(), stderr_fd)
            yield
            sys.stderr.flush()
    finally:
        os.dup2(saved_fd, stderr_fd)
        os.close(saved_fd)


@dataclass(frozen=True)
class DistortionWeights:
    """Weights for the heuristic score; these should be calibrated on labeled data."""

    clipping: float = 0.35
    high_frequency: float = 0.25
    low_crest_factor: float = 0.20
    spectral_irregularity: float = 0.20

    def normalized(self) -> np.ndarray:
        values = np.asarray(
            [
                self.clipping,
                self.high_frequency,
                self.low_crest_factor,
                self.spectral_irregularity,
            ],
            dtype=np.float64,
        )
        if np.any(values < 0.0) or float(np.sum(values)) <= EPSILON:
            raise AudioAnalysisError("Distortion weights must be non-negative and sum above zero.")
        return values / np.sum(values)


@dataclass(frozen=True)
class AnalyzerConfig:
    frame_length: int = 2048
    hop_length: int = 512
    noise_percentile: float = 15.0
    clipping_threshold: float = 0.99
    bass_max_frequency: float = 250.0
    treble_min_frequency: float = 4000.0
    silence_threshold_dbfs: float = -60.0
    minimum_duration_seconds: float = 0.10
    distortion_high_frequency_start: float = 6000.0
    excessive_high_frequency_ratio: float = 0.20
    healthy_crest_factor_db: float = 12.0
    poor_crest_factor_db: float = 3.0
    severe_clipped_sample_percentage: float = 0.50
    severe_clipped_frame_percentage: float = 20.0
    severe_spectral_irregularity: float = 0.35
    distortion_weights: DistortionWeights = field(default_factory=DistortionWeights)


@dataclass(frozen=True)
class SafetyLimits:
    maximum_file_size_mb: float = 100.0
    maximum_duration_seconds: float = 900.0
    minimum_recovered_percentage: float = 90.0
    minimum_recovered_duration_seconds: float = 5.0
    minimum_active_frames: int = 10


@dataclass(frozen=True)
class QualityThresholds:
    snr_warning_below_db: float = 10.0
    snr_failure_below_db: float = 5.0
    distortion_warning_above: float = 20.0
    distortion_failure_above: float = 50.0
    clipped_samples_failure_above_percentage: float = 0.5


@dataclass(frozen=True)
class FailureBehavior:
    save_outputs_on_quality_failure: bool = True
    quality_failure_exit_code: int = 3
    record_technical_failures_in_csv: bool = True
    cleanup_incomplete_outputs: bool = True


@dataclass(frozen=True)
class AudioAnalyzerSettings:
    analysis: AnalyzerConfig
    safety: SafetyLimits
    quality_thresholds: QualityThresholds
    failure_behavior: FailureBehavior
    settings_path: Path


@dataclass(frozen=True)
class AnalysisContext:
    audio: np.ndarray
    sample_rate: int
    magnitude: np.ndarray
    power: np.ndarray
    frequencies: np.ndarray
    frame_times: np.ndarray
    frame_rms: np.ndarray
    active_frames: np.ndarray
    flatness: np.ndarray
    config: AnalyzerConfig


def _validate_config(config: AnalyzerConfig) -> None:
    if config.frame_length < 32:
        raise AudioAnalysisError("Frame length must be at least 32 samples.")
    if config.hop_length < 1 or config.hop_length > config.frame_length:
        raise AudioAnalysisError("Hop length must be between 1 and the frame length.")
    if not 0.0 < config.noise_percentile <= 50.0:
        raise AudioAnalysisError("Noise percentile must be greater than 0 and at most 50.")
    if not 0.0 < config.clipping_threshold <= 1.0:
        raise AudioAnalysisError("Clipping threshold must be in the interval (0, 1].")
    if config.bass_max_frequency <= 20.0:
        raise AudioAnalysisError("Bass maximum frequency must be above 20 Hz.")
    if config.treble_min_frequency <= 0.0:
        raise AudioAnalysisError("Treble minimum frequency must be positive.")
    if config.silence_threshold_dbfs >= 0.0:
        raise AudioAnalysisError("Silence threshold must be below 0 dBFS.")
    if config.minimum_duration_seconds <= 0.0:
        raise AudioAnalysisError("Minimum duration must be positive.")
    if config.distortion_high_frequency_start <= 0.0:
        raise AudioAnalysisError("Distortion high-frequency start must be positive.")
    if not 0.0 < config.excessive_high_frequency_ratio < 1.0:
        raise AudioAnalysisError("Excessive high-frequency ratio must be between 0 and 1.")
    if config.poor_crest_factor_db < 0.0:
        raise AudioAnalysisError("Poor crest factor must be non-negative.")
    if config.healthy_crest_factor_db <= config.poor_crest_factor_db:
        raise AudioAnalysisError("Healthy crest factor must exceed the poor crest factor.")
    if config.severe_clipped_sample_percentage <= 0.0:
        raise AudioAnalysisError("Severe clipped-sample percentage must be positive.")
    if config.severe_clipped_frame_percentage <= 0.0:
        raise AudioAnalysisError("Severe clipped-frame percentage must be positive.")
    if config.severe_spectral_irregularity <= 0.0:
        raise AudioAnalysisError("Severe spectral irregularity must be positive.")
    config.distortion_weights.normalized()


def _section(data: dict[str, Any], name: str) -> dict[str, Any]:
    value = data.get(name, {})
    if not isinstance(value, dict):
        raise AudioAnalysisError(f"Settings section '{name}' must be a JSON object.")
    return value


def _reject_unknown_keys(section: dict[str, Any], allowed: set[str], name: str) -> None:
    unknown = sorted(set(section) - allowed)
    if unknown:
        raise AudioAnalysisError(
            f"Unknown setting(s) in '{name}': {', '.join(unknown)}. "
            "Correct the spelling or remove them."
        )


def _validate_safety(limits: SafetyLimits) -> None:
    if limits.maximum_file_size_mb <= 0.0:
        raise AudioAnalysisError("Maximum file size must be positive.")
    if limits.maximum_duration_seconds <= 0.0:
        raise AudioAnalysisError("Maximum duration must be positive.")
    if not 0.0 < limits.minimum_recovered_percentage <= 100.0:
        raise AudioAnalysisError("Minimum recovered percentage must be in (0, 100].")
    if limits.minimum_recovered_duration_seconds <= 0.0:
        raise AudioAnalysisError("Minimum recovered duration must be positive.")
    if limits.minimum_active_frames < 1:
        raise AudioAnalysisError("Minimum active frames must be at least 1.")


def _validate_quality_thresholds(thresholds: QualityThresholds) -> None:
    if thresholds.snr_failure_below_db > thresholds.snr_warning_below_db:
        raise AudioAnalysisError("SNR failure threshold cannot exceed its warning threshold.")
    if not 0.0 <= thresholds.distortion_warning_above <= 100.0:
        raise AudioAnalysisError("Distortion warning threshold must be between 0 and 100.")
    if not 0.0 <= thresholds.distortion_failure_above <= 100.0:
        raise AudioAnalysisError("Distortion failure threshold must be between 0 and 100.")
    if thresholds.distortion_failure_above < thresholds.distortion_warning_above:
        raise AudioAnalysisError("Distortion failure threshold cannot be below its warning threshold.")
    if not 0.0 <= thresholds.clipped_samples_failure_above_percentage <= 100.0:
        raise AudioAnalysisError("Clipped-sample failure threshold must be between 0 and 100.")


def _validate_failure_behavior(behavior: FailureBehavior) -> None:
    for name in (
        "save_outputs_on_quality_failure",
        "record_technical_failures_in_csv",
        "cleanup_incomplete_outputs",
    ):
        if not isinstance(getattr(behavior, name), bool):
            raise AudioAnalysisError(f"Failure behavior '{name}' must be true or false.")
    if not isinstance(behavior.quality_failure_exit_code, int) or not (
        1 <= behavior.quality_failure_exit_code <= 255
    ):
        raise AudioAnalysisError("Quality failure exit code must be an integer from 1 to 255.")


def load_settings(settings_path: str | Path = DEFAULT_SETTINGS_PATH) -> AudioAnalyzerSettings:
    """Load, merge, and strictly validate the versioned JSON settings file."""
    path = Path(settings_path).expanduser().resolve()
    if not path.exists() or not path.is_file():
        raise AudioAnalysisError(f"Settings file does not exist: {path}")
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise AudioAnalysisError(
            f"Settings file contains invalid JSON at line {exc.lineno}, column {exc.colno}: {exc.msg}"
        ) from exc
    except OSError as exc:
        raise AudioAnalysisError(f"Could not read settings file '{path}': {exc}") from exc
    if not isinstance(raw, dict):
        raise AudioAnalysisError("Settings file root must be a JSON object.")

    allowed_top_level = {
        "schema_version",
        "analysis",
        "safety",
        "quality_thresholds",
        "failure_behavior",
    }
    _reject_unknown_keys(raw, allowed_top_level, "root")
    if raw.get("schema_version") != 1:
        raise AudioAnalysisError("Unsupported settings schema_version; expected 1.")

    analysis_data = _section(raw, "analysis")
    analysis_allowed = set(AnalyzerConfig.__dataclass_fields__)
    _reject_unknown_keys(analysis_data, analysis_allowed, "analysis")
    weights_data = analysis_data.get("distortion_weights", {})
    if not isinstance(weights_data, dict):
        raise AudioAnalysisError("Setting 'analysis.distortion_weights' must be a JSON object.")
    _reject_unknown_keys(
        weights_data,
        set(DistortionWeights.__dataclass_fields__),
        "analysis.distortion_weights",
    )
    default_analysis = AnalyzerConfig()
    default_weights = DistortionWeights()
    weights = DistortionWeights(
        **{
            name: weights_data.get(name, getattr(default_weights, name))
            for name in DistortionWeights.__dataclass_fields__
        }
    )
    analysis = AnalyzerConfig(
        **{
            name: analysis_data.get(name, getattr(default_analysis, name))
            for name in AnalyzerConfig.__dataclass_fields__
            if name != "distortion_weights"
        },
        distortion_weights=weights,
    )

    safety_data = _section(raw, "safety")
    _reject_unknown_keys(safety_data, set(SafetyLimits.__dataclass_fields__), "safety")
    default_safety = SafetyLimits()
    safety = SafetyLimits(
        **{
            name: safety_data.get(name, getattr(default_safety, name))
            for name in SafetyLimits.__dataclass_fields__
        }
    )

    quality_data = _section(raw, "quality_thresholds")
    _reject_unknown_keys(
        quality_data,
        set(QualityThresholds.__dataclass_fields__),
        "quality_thresholds",
    )
    default_quality = QualityThresholds()
    quality = QualityThresholds(
        **{
            name: quality_data.get(name, getattr(default_quality, name))
            for name in QualityThresholds.__dataclass_fields__
        }
    )

    behavior_data = _section(raw, "failure_behavior")
    _reject_unknown_keys(
        behavior_data,
        set(FailureBehavior.__dataclass_fields__),
        "failure_behavior",
    )
    default_behavior = FailureBehavior()
    behavior = FailureBehavior(
        **{
            name: behavior_data.get(name, getattr(default_behavior, name))
            for name in FailureBehavior.__dataclass_fields__
        }
    )

    try:
        _validate_config(analysis)
        _validate_safety(safety)
        _validate_quality_thresholds(quality)
        _validate_failure_behavior(behavior)
    except TypeError as exc:
        raise AudioAnalysisError(f"Settings values have invalid data types: {exc}") from exc
    return AudioAnalyzerSettings(analysis, safety, quality, behavior, path)


def _recover_readable_prefix(
    path: Path,
    primary_error: Exception,
    safety: SafetyLimits,
) -> tuple[np.ndarray, int, dict[str, Any]]:
    """Decode complete blocks until damaged input prevents further reading.

    This intentionally recovers only a continuous prefix. It never skips an
    unknown damaged region and joins unrelated audio on either side of it.
    """
    chunks: list[np.ndarray] = []
    read_error: Exception | None = None
    recovered_frame_count = 0
    try:
        with sf.SoundFile(str(path)) as decoder:
            sample_rate = int(decoder.samplerate)
            channels = int(decoder.channels)
            declared_frames = int(decoder.frames)
            container_format = decoder.format
            container_subtype = decoder.subtype
            while True:
                try:
                    with _suppress_native_decoder_diagnostics():
                        block = cast(
                            np.ndarray,
                            decoder.read(
                                RECOVERY_BLOCK_FRAMES,
                                dtype="float32",
                                always_2d=True,
                            ),
                        )
                except Exception as exc:
                    read_error = exc
                    break
                if block.shape[0] == 0:
                    break
                mono_block = np.asarray(
                    np.mean(block, axis=1, dtype=np.float32),
                    dtype=np.float32,
                )
                chunks.append(mono_block)
                recovered_frame_count += int(mono_block.size)
                if recovered_frame_count / max(sample_rate, 1) > safety.maximum_duration_seconds:
                    raise AudioAnalysisError(
                        f"Recovered audio exceeds the configured maximum duration of "
                        f"{safety.maximum_duration_seconds:.3f} seconds."
                    )
    except AudioAnalysisError:
        raise
    except Exception as recovery_error:
        primary_detail = str(primary_error).strip() or type(primary_error).__name__
        recovery_detail = str(recovery_error).strip() or type(recovery_error).__name__
        raise AudioAnalysisError(
            f"Could not decode '{path.name}'. Primary decoder: {primary_detail}. "
            f"Recovery decoder: {recovery_detail}."
        ) from recovery_error

    if not chunks:
        detail = str(read_error or primary_error).strip() or type(read_error or primary_error).__name__
        raise AudioAnalysisError(
            f"Could not recover any readable audio from '{path.name}': {detail}."
        ) from (read_error or primary_error)

    audio = np.concatenate(chunks).astype(np.float32, copy=False)
    recovered_frames = int(audio.size)
    recovered_duration = recovered_frames / max(sample_rate, 1)
    declared_duration = declared_frames / max(sample_rate, 1) if declared_frames > 0 else 0.0
    discarded_frames = max(0, declared_frames - recovered_frames)
    discarded_duration = discarded_frames / max(sample_rate, 1)
    recovered_percentage = (
        100.0 * recovered_frames / declared_frames if declared_frames > 0 else 100.0
    )

    if read_error is None:
        decode_status = "fallback_complete"
        warning = (
            "The normal decoder failed, but chunked decoding reached the end of the file. "
            "Results use the complete chunk-decoded signal."
        )
    else:
        if recovered_duration < safety.minimum_recovered_duration_seconds:
            raise AudioAnalysisError(
                f"Only {recovered_duration:.3f} seconds could be recovered; at least "
                f"{safety.minimum_recovered_duration_seconds:.3f} seconds is required."
            )
        if recovered_percentage < safety.minimum_recovered_percentage:
            raise AudioAnalysisError(
                f"Only {recovered_percentage:.3f}% of declared audio frames could be recovered; "
                f"at least {safety.minimum_recovered_percentage:.3f}% is required."
            )
        decode_status = "recovered_partial"
        warning = (
            f"Input corruption was detected. Analysis uses the readable {recovered_duration:.3f}-second "
            f"prefix ({recovered_percentage:.3f}% of declared frames); approximately "
            f"{discarded_duration:.3f} seconds at the damaged tail were discarded."
        )

    return audio, sample_rate, {
        "container_format": container_format,
        "container_subtype": container_subtype,
        "source_channels": channels,
        "decode_status": decode_status,
        "declared_duration_seconds": float(declared_duration),
        "recovered_frame_percentage": float(recovered_percentage),
        "discarded_duration_seconds": float(discarded_duration),
        "recovery_warning": warning,
    }


def load_audio(
    file_path: str | Path,
    safety: SafetyLimits | None = None,
) -> tuple[np.ndarray, int, dict[str, Any]]:
    """Load normally with Librosa, or recover a continuous readable prefix."""
    safety = safety or SafetyLimits()
    _validate_safety(safety)
    path = Path(file_path).expanduser().resolve()
    if not path.exists():
        raise AudioAnalysisError(f"Audio file does not exist: {path}")
    if not path.is_file():
        raise AudioAnalysisError(f"Audio path is not a regular file: {path}")
    if path.suffix.lower() not in SUPPORTED_EXTENSIONS:
        supported = ", ".join(sorted(SUPPORTED_EXTENSIONS))
        raise AudioAnalysisError(f"Unsupported audio format '{path.suffix}'. Supported: {supported}")
    if path.stat().st_size == 0:
        raise AudioAnalysisError(f"Audio file is empty: {path}")
    maximum_bytes = int(safety.maximum_file_size_mb * 1024 * 1024)
    if path.stat().st_size > maximum_bytes:
        raise AudioAnalysisError(
            f"Audio file is {path.stat().st_size / (1024 * 1024):.2f} MB; the configured "
            f"maximum is {safety.maximum_file_size_mb:.4g} MB."
        )

    # Passing a SoundFile decoder to Librosa keeps Librosa as the normal loading
    # interface while preventing its deprecated audioread fallback from hiding
    # the original libsndfile failure. A failed full read then triggers recovery.
    try:
        decoder = sf.SoundFile(str(path))
    except Exception:
        decoder = None

    if decoder is not None:
        declared_duration = float(decoder.frames / decoder.samplerate)
        if declared_duration > safety.maximum_duration_seconds:
            decoder.close()
            raise AudioAnalysisError(
                f"Declared audio duration is {declared_duration:.3f} seconds; the configured "
                f"maximum is {safety.maximum_duration_seconds:.3f} seconds."
            )
        container_info: dict[str, Any] = {
            "container_format": decoder.format,
            "container_subtype": decoder.subtype,
            "source_channels": int(decoder.channels),
            "decode_status": "complete",
            "declared_duration_seconds": declared_duration,
            "recovered_frame_percentage": 100.0,
            "discarded_duration_seconds": 0.0,
            "recovery_warning": "",
        }
        try:
            with _suppress_native_decoder_diagnostics():
                audio, sample_rate = librosa.load(
                    decoder,
                    sr=None,
                    mono=True,
                    dtype=np.float32,
                )
        except Exception as exc:
            return _recover_readable_prefix(path, exc, safety)
    else:
        # Audioread may still support a codec that the local libsndfile build
        # cannot open, so retain Librosa's path-based fallback for that case.
        try:
            with _suppress_native_decoder_diagnostics():
                audio, sample_rate = librosa.load(
                    str(path),
                    sr=None,
                    mono=True,
                    dtype=np.float32,
                )
        except Exception as exc:
            detail = str(exc).strip() or type(exc).__name__
            raise AudioAnalysisError(
                f"Could not decode '{path.name}'. The file may be invalid, corrupted, "
                f"or use an unavailable codec: {detail}."
            ) from exc
        container_info = {
            "decode_status": "complete",
            "recovered_frame_percentage": 100.0,
            "discarded_duration_seconds": 0.0,
            "recovery_warning": "",
        }

    decoded = np.asarray(audio, dtype=np.float32)
    decoded_duration = decoded.size / max(int(sample_rate), 1)
    if decoded_duration > safety.maximum_duration_seconds:
        raise AudioAnalysisError(
            f"Decoded audio duration is {decoded_duration:.3f} seconds; the configured maximum "
            f"is {safety.maximum_duration_seconds:.3f} seconds."
        )
    return decoded, int(sample_rate), container_info


def validate_audio(audio: np.ndarray, sample_rate: int, config: AnalyzerConfig) -> np.ndarray:
    """Validate and safely constrain audio without destroying its dBFS level."""
    _validate_config(config)
    if sample_rate <= 0:
        raise AudioAnalysisError("Decoded audio has an invalid sampling rate.")
    if audio.ndim != 1:
        raise AudioAnalysisError("Decoded audio must be mono.")
    if audio.size == 0:
        raise AudioAnalysisError("Decoded audio contains no samples.")
    if not np.all(np.isfinite(audio)):
        raise AudioAnalysisError("Decoded audio contains NaN or infinite samples.")

    duration = audio.size / sample_rate
    if duration < config.minimum_duration_seconds:
        raise AudioAnalysisError(
            f"Audio is too short ({duration:.3f} s); at least {config.minimum_duration_seconds:.3f} s is required."
        )
    if audio.size < config.frame_length:
        raise AudioAnalysisError(
            f"Audio has {audio.size} samples, fewer than frame length {config.frame_length}. "
            "Use a smaller --frame-length or a longer recording."
        )

    peak = float(np.max(np.abs(audio)))
    if peak <= EPSILON:
        raise AudioAnalysisError("Audio is silent or numerically empty; no features can be estimated.")

    # Scaling only values outside full scale is a safe normalization. Scaling a
    # quiet file up to 1.0 would invalidate its loudness and noise-floor dBFS.
    normalized = audio / peak if peak > 1.0 else audio.copy()
    return np.clip(normalized, -1.0, 1.0)


def compute_stft(
    audio: np.ndarray,
    sample_rate: int,
    frame_length: int,
    hop_length: int,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Return magnitude, power, FFT-bin frequencies, and frame-center times."""
    stft = librosa.stft(
        audio,
        n_fft=frame_length,
        hop_length=hop_length,
        win_length=frame_length,
        window="hann",
        center=False,
    )
    magnitude = np.abs(stft)
    power = np.square(magnitude)
    frequencies = librosa.fft_frequencies(sr=sample_rate, n_fft=frame_length)
    frame_numbers = np.arange(magnitude.shape[1])
    times = librosa.frames_to_time(
        frame_numbers,
        sr=sample_rate,
        hop_length=hop_length,
        n_fft=frame_length,
    )
    return magnitude, power, frequencies, times


def _active_frame_mask(
    frame_rms: np.ndarray,
    config: AnalyzerConfig,
    minimum_active_frames: int,
) -> tuple[np.ndarray, float]:
    absolute_threshold = float(librosa.db_to_amplitude(config.silence_threshold_dbfs))
    adaptive_threshold = float(np.max(frame_rms)) * 0.01  # 40 dB below the loudest frame
    threshold = max(EPSILON, min(absolute_threshold, adaptive_threshold))
    active = frame_rms > threshold
    active_count = int(np.sum(active))
    if active_count < minimum_active_frames:
        raise AudioAnalysisError(
            f"Only {active_count} non-silent frames remain after filtering; at least "
            f"{minimum_active_frames} are required. Check the recording or silence threshold."
        )
    return active, threshold


def _band_rms(
    magnitude: np.ndarray,
    band_mask: np.ndarray,
    active_frames: np.ndarray,
    frame_length: int,
) -> float:
    if not np.any(band_mask):
        return 0.0
    band_magnitude = np.zeros_like(magnitude)
    band_magnitude[band_mask, :] = magnitude[band_mask, :]
    # librosa's spectral RMS applies the correct one-sided FFT energy scaling.
    rms = librosa.feature.rms(S=band_magnitude, frame_length=frame_length)[0]
    # STFT frames use a Hann window, whose RMS gain is below 1. Compensating for
    # that gain expresses the result on the same amplitude scale as time RMS.
    window = hann(frame_length)
    window_rms_gain = float(np.sqrt(np.mean(np.square(window))))
    return float(np.mean(rms[active_frames]) / max(window_rms_gain, EPSILON))


def _band_features(
    magnitude: np.ndarray,
    power: np.ndarray,
    frequencies: np.ndarray,
    active_frames: np.ndarray,
    frame_length: int,
    minimum_hz: float,
    maximum_hz: float,
) -> dict[str, float]:
    band = (frequencies >= minimum_hz) & (frequencies <= maximum_hz)
    total_energy = float(np.sum(power[:, active_frames], dtype=np.float64))
    band_energy = (
        float(np.sum(power[band, :][:, active_frames], dtype=np.float64))
        if np.any(band)
        else 0.0
    )
    return {
        "rms": _band_rms(magnitude, band, active_frames, frame_length),
        "energy_percentage": 100.0 * band_energy / max(total_energy, EPSILON),
        "minimum_frequency_hz": float(minimum_hz),
        "maximum_frequency_hz": float(maximum_hz),
    }


def extract_bass_features(context: AnalysisContext) -> dict[str, float]:
    nyquist = context.sample_rate / 2.0
    maximum = min(context.config.bass_max_frequency, nyquist)
    return _band_features(
        context.magnitude,
        context.power,
        context.frequencies,
        context.active_frames,
        context.config.frame_length,
        20.0,
        maximum,
    )


def extract_treble_features(context: AnalysisContext) -> dict[str, float]:
    nyquist = context.sample_rate / 2.0
    # If 4 kHz is at or beyond Nyquist, use the highest quarter of the available
    # spectrum rather than returning an empty or single-bin measurement.
    effective_minimum = (
        context.config.treble_min_frequency
        if context.config.treble_min_frequency < nyquist
        else 0.75 * nyquist
    )
    return _band_features(
        context.magnitude,
        context.power,
        context.frequencies,
        context.active_frames,
        context.config.frame_length,
        effective_minimum,
        nyquist,
    )


def extract_loudness(context: AnalysisContext) -> dict[str, float]:
    active_rms = np.maximum(context.frame_rms[context.active_frames], EPSILON)
    # ref=1.0 makes 0 dBFS full scale; clipping avoids log10(0) and -infinity.
    loudness_dbfs = librosa.amplitude_to_db(active_rms, ref=1.0, top_db=None)
    return {
        "mean_dbfs": float(np.mean(loudness_dbfs)),
        "median_dbfs": float(np.median(loudness_dbfs)),
        "minimum_dbfs": float(np.min(loudness_dbfs)),
        "maximum_dbfs": float(np.max(loudness_dbfs)),
        "standard_deviation_db": float(np.std(loudness_dbfs)),
    }


def extract_flatness(context: AnalysisContext) -> dict[str, Any]:
    values = context.flatness[context.active_frames]
    return {
        "mean": float(np.mean(values)),
        "standard_deviation": float(np.std(values)),
        "interpretation": "Values near 1 are noise-like; values near 0 are tonal.",
    }


def estimate_sharpness(context: AnalysisContext) -> dict[str, Any]:
    nyquist = max(context.sample_rate / 2.0, EPSILON)
    normalized_frequency = np.clip(context.frequencies / nyquist, 0.0, 1.0)
    active_power = context.power[:, context.active_frames]
    # The second normalized spectral moment emphasizes high-frequency energy.
    # It is bounded to [0, 1], unlike certified psychoacoustic sharpness in acum.
    numerator = np.sum(active_power * np.square(normalized_frequency)[:, np.newaxis], axis=0)
    denominator = np.sum(active_power, axis=0)
    frame_scores = numerator / np.maximum(denominator, EPSILON)
    return {
        "normalized_score": float(np.clip(np.mean(frame_scores), 0.0, 1.0)),
        "interpretation": "Approximate high-frequency-weighted spectral score; not sharpness in acum.",
    }


def estimate_noise(context: AnalysisContext) -> dict[str, Any]:
    # Silent and quiet frames are excluded from normal feature averages, but are
    # intentionally retained here because they are the candidates for a noise
    # floor. validate_audio() has already rejected a wholly silent recording.
    candidate_rms = context.frame_rms
    cutoff = float(np.percentile(candidate_rms, context.config.noise_percentile))
    quiet_frames = candidate_rms[candidate_rms <= cutoff]
    noise_rms = float(np.sqrt(np.mean(np.square(quiet_frames))))
    signal_rms = float(
        np.sqrt(np.mean(np.square(context.frame_rms[context.active_frames])))
    )
    noise_dbfs = 20.0 * math.log10(max(noise_rms, EPSILON))
    estimated_snr_db = 20.0 * math.log10(max(signal_rms, EPSILON) / max(noise_rms, EPSILON))

    separation_db = 20.0 * math.log10(max(signal_rms, EPSILON) / max(cutoff, EPSILON))
    warning = (
        "The recording has little level separation between typical and quiet frames; "
        "it may contain no true quiet section, so this noise estimate is unreliable."
        if separation_db < 6.0
        else "Low-energy frames may contain wanted audio; treat this no-reference noise estimate cautiously."
    )
    return {
        "noise_rms": noise_rms,
        "noise_dbfs": float(noise_dbfs),
        "estimated_snr_db": float(estimated_snr_db),
        "low_energy_percentile": float(context.config.noise_percentile),
        "quiet_frame_count": int(quiet_frames.size),
        "reliability_warning": warning,
    }


def estimate_distortion(context: AnalysisContext) -> dict[str, Any]:
    audio = context.audio
    config = context.config
    absolute_audio = np.abs(audio)
    clipped_samples = absolute_audio >= config.clipping_threshold
    clipped_sample_percentage = 100.0 * float(np.mean(clipped_samples))

    framed_audio = librosa.util.frame(
        audio,
        frame_length=config.frame_length,
        hop_length=config.hop_length,
    )
    clipped_by_frame = np.any(np.abs(framed_audio) >= config.clipping_threshold, axis=0)
    clipped_frame_percentage = 100.0 * float(np.mean(clipped_by_frame[context.active_frames]))

    aggregate_rms = float(
        np.sqrt(np.mean(np.square(context.frame_rms[context.active_frames])))
    )
    peak = float(np.max(absolute_audio))
    crest_factor_db = 20.0 * math.log10(max(peak, EPSILON) / max(aggregate_rms, EPSILON))

    nyquist = context.sample_rate / 2.0
    high_frequency_start = min(config.distortion_high_frequency_start, 0.75 * nyquist)
    high_band = context.frequencies >= high_frequency_start
    active_power = context.power[:, context.active_frames]
    high_frequency_energy_ratio = float(
        np.sum(active_power[high_band, :]) / max(float(np.sum(active_power)), EPSILON)
    )

    harmonic, percussive = librosa.decompose.hpss(context.magnitude)
    harmonic_energy = float(np.sum(np.square(harmonic[:, context.active_frames])))
    percussive_energy = float(np.sum(np.square(percussive[:, context.active_frames])))
    harmonic_to_percussive_energy_ratio = harmonic_energy / max(percussive_energy, EPSILON)

    normalized_spectra = active_power / np.maximum(
        np.sum(active_power, axis=0, keepdims=True), EPSILON
    )
    if normalized_spectra.shape[1] > 1:
        # L2 spectral flux is a bounded proxy for frame-to-frame irregularity.
        flux = np.sqrt(np.sum(np.square(np.diff(normalized_spectra, axis=1)), axis=0) / 2.0)
        spectral_irregularity = float(np.clip(np.mean(flux), 0.0, 1.0))
    else:
        spectral_irregularity = 0.0

    clipping_risk = max(
        clipped_sample_percentage / max(config.severe_clipped_sample_percentage, EPSILON),
        clipped_frame_percentage / max(config.severe_clipped_frame_percentage, EPSILON),
    )
    high_frequency_risk = (
        high_frequency_energy_ratio - config.excessive_high_frequency_ratio
    ) / max(1.0 - config.excessive_high_frequency_ratio, EPSILON)
    crest_factor_risk = (
        config.healthy_crest_factor_db - crest_factor_db
    ) / max(config.healthy_crest_factor_db - config.poor_crest_factor_db, EPSILON)
    irregularity_risk = spectral_irregularity / max(
        config.severe_spectral_irregularity, EPSILON
    )
    risks = np.clip(
        [clipping_risk, high_frequency_risk, crest_factor_risk, irregularity_risk],
        0.0,
        1.0,
    )
    estimated_score = 100.0 * float(np.dot(config.distortion_weights.normalized(), risks))

    if estimated_score < 20.0:
        interpretation = "Low heuristic distortion risk; this is not a THD measurement."
    elif estimated_score < 50.0:
        interpretation = "Moderate heuristic distortion risk; inspect the component metrics and recording."
    else:
        interpretation = "High heuristic distortion risk; clipping or other artifacts may be present."

    return {
        "estimated_score": float(np.clip(estimated_score, 0.0, 100.0)),
        "clipped_sample_percentage": clipped_sample_percentage,
        "clipped_frame_percentage": clipped_frame_percentage,
        "crest_factor_db": float(crest_factor_db),
        "high_frequency_energy_ratio": high_frequency_energy_ratio,
        "high_frequency_start_hz": float(high_frequency_start),
        "harmonic_to_percussive_energy_ratio": float(harmonic_to_percussive_energy_ratio),
        "spectral_irregularity": spectral_irregularity,
        "component_risks": {
            "clipping": float(risks[0]),
            "high_frequency": float(risks[1]),
            "low_crest_factor": float(risks[2]),
            "spectral_irregularity": float(risks[3]),
        },
        "interpretation": interpretation,
    }


def evaluate_quality(
    results: dict[str, Any],
    thresholds: QualityThresholds,
) -> dict[str, Any]:
    """Apply configurable deterministic warning/failure thresholds."""
    _validate_quality_thresholds(thresholds)
    snr_db = float(results["noise"]["estimated_snr_db"])
    distortion_score = float(results["distortion"]["estimated_score"])
    clipped_percentage = float(results["distortion"]["clipped_sample_percentage"])
    warnings: list[str] = []
    failures: list[str] = []

    if snr_db < thresholds.snr_failure_below_db:
        failures.append(
            f"Estimated SNR {snr_db:.2f} dB is below the failure threshold "
            f"{thresholds.snr_failure_below_db:.2f} dB."
        )
    elif snr_db < thresholds.snr_warning_below_db:
        warnings.append(
            f"Estimated SNR {snr_db:.2f} dB is below the warning threshold "
            f"{thresholds.snr_warning_below_db:.2f} dB."
        )

    if distortion_score > thresholds.distortion_failure_above:
        failures.append(
            f"Distortion score {distortion_score:.2f} exceeds the failure threshold "
            f"{thresholds.distortion_failure_above:.2f}."
        )
    elif distortion_score > thresholds.distortion_warning_above:
        warnings.append(
            f"Distortion score {distortion_score:.2f} exceeds the warning threshold "
            f"{thresholds.distortion_warning_above:.2f}."
        )

    if clipped_percentage > thresholds.clipped_samples_failure_above_percentage:
        failures.append(
            f"Clipped samples {clipped_percentage:.4f}% exceed the failure threshold "
            f"{thresholds.clipped_samples_failure_above_percentage:.4f}%."
        )

    status = "failed" if failures else "warning" if warnings else "passed"
    return {
        "status": status,
        "warnings": warnings,
        "failures": failures,
        "measured": {
            "estimated_snr_db": snr_db,
            "estimated_distortion_score": distortion_score,
            "clipped_sample_percentage": clipped_percentage,
        },
        "thresholds": {
            "snr_warning_below_db": float(thresholds.snr_warning_below_db),
            "snr_failure_below_db": float(thresholds.snr_failure_below_db),
            "distortion_warning_above": float(thresholds.distortion_warning_above),
            "distortion_failure_above": float(thresholds.distortion_failure_above),
            "clipped_samples_failure_above_percentage": float(
                thresholds.clipped_samples_failure_above_percentage
            ),
        },
    }


def _analyze_with_context(
    file_path: str | Path,
    config: AnalyzerConfig | None = None,
    safety: SafetyLimits | None = None,
) -> tuple[dict[str, Any], AnalysisContext]:
    config = config or AnalyzerConfig()
    safety = safety or SafetyLimits()
    _validate_config(config)
    _validate_safety(safety)
    raw_audio, sample_rate, container_info = load_audio(file_path, safety)
    audio = validate_audio(raw_audio, sample_rate, config)
    magnitude, power, frequencies, frame_times = compute_stft(
        audio, sample_rate, config.frame_length, config.hop_length
    )
    frame_rms = librosa.feature.rms(
        y=audio,
        frame_length=config.frame_length,
        hop_length=config.hop_length,
        center=False,
    )[0]
    if frame_rms.size != magnitude.shape[1]:
        raise AudioAnalysisError("Internal frame alignment error during analysis.")
    active_frames, silence_threshold = _active_frame_mask(
        frame_rms,
        config,
        safety.minimum_active_frames,
    )
    flatness = librosa.feature.spectral_flatness(S=magnitude)[0]

    context = AnalysisContext(
        audio=audio,
        sample_rate=sample_rate,
        magnitude=magnitude,
        power=power,
        frequencies=frequencies,
        frame_times=frame_times,
        frame_rms=frame_rms,
        active_frames=active_frames,
        flatness=flatness,
        config=config,
    )
    path = Path(file_path).expanduser().resolve()
    results: dict[str, Any] = {
        "file_information": {
            "file_path": str(path),
            "sample_rate": sample_rate,
            "duration_seconds": float(audio.size / sample_rate),
            "number_of_samples": int(audio.size),
            **container_info,
        },
        "analysis_information": {
            "frame_length": config.frame_length,
            "hop_length": config.hop_length,
            "total_frame_count": int(frame_rms.size),
            "analyzed_frame_count": int(np.sum(active_frames)),
            "ignored_silent_frame_count": int(np.sum(~active_frames)),
            "effective_silence_threshold_dbfs": float(
                20.0 * math.log10(max(silence_threshold, EPSILON))
            ),
        },
        "bass": extract_bass_features(context),
        "treble": extract_treble_features(context),
        "loudness": extract_loudness(context),
        "flatness": extract_flatness(context),
        "sharpness": estimate_sharpness(context),
        "noise": estimate_noise(context),
        "distortion": estimate_distortion(context),
    }
    return results, context


def analyze_audio(
    file_path: str | Path,
    config: AnalyzerConfig | None = None,
    safety: SafetyLimits | None = None,
    quality_thresholds: QualityThresholds | None = None,
) -> dict[str, Any]:
    """Analyze an audio file and return a JSON-serializable result dictionary."""
    results, _ = _analyze_with_context(file_path, config, safety)
    results["quality_assessment"] = evaluate_quality(
        results,
        quality_thresholds or QualityThresholds(),
    )
    return results


def _unique_prefix(file_path: str | Path) -> str:
    stem = re.sub(r"[^A-Za-z0-9._-]+", "_", Path(file_path).stem).strip("._") or "audio"
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ")
    return f"{stem}_{stamp}"


def _shared_results_csv_path(destination: Path) -> Path:
    """Locate the nearest results directory, or use the output directory itself."""
    for candidate in (destination, *destination.parents):
        if candidate.name.lower() == "results":
            return candidate / "results.csv"
    return destination / "results.csv"


def _analysis_timestamp(prefix: str) -> str:
    match = re.search(r"(\d{8}T\d{6}_\d{6}Z)$", prefix)
    if match:
        parsed = datetime.strptime(match.group(1), "%Y%m%dT%H%M%S_%fZ").replace(
            tzinfo=timezone.utc
        )
        return parsed.isoformat()
    return datetime.now(timezone.utc).isoformat()


def _append_shared_csv(
    results: dict[str, Any],
    destination: Path,
    prefix: str,
) -> Path:
    """Append one analysis to the shared CSV, safely accommodating new columns."""
    csv_path = _shared_results_csv_path(destination)
    csv_path.parent.mkdir(parents=True, exist_ok=True)

    row = pd.json_normalize(results, sep=".")
    row.insert(0, "output_directory", str(destination))
    row.insert(0, "analyzed_at_utc", _analysis_timestamp(prefix))
    row.insert(0, "analysis_id", prefix)

    if csv_path.exists() and csv_path.stat().st_size > 0:
        existing = pd.read_csv(csv_path)
        if "analysis_id" in existing.columns:
            existing = existing[existing["analysis_id"].astype(str) != prefix]
        columns = list(dict.fromkeys([*existing.columns, *row.columns]))
        combined = existing.reindex(columns=columns).astype(object)
        aligned_row = row.reindex(columns=columns).astype(object)
        combined.loc[len(combined)] = aligned_row.iloc[0]
    else:
        combined = row

    # Replace atomically so an interrupted write does not truncate prior rows.
    temporary_path = csv_path.with_name(f".{prefix}.{csv_path.name}.tmp")
    combined.to_csv(temporary_path, index=False, encoding="utf-8")
    os.replace(temporary_path, csv_path)
    return csv_path


def save_results(
    results: dict[str, Any],
    output_dir: str | Path,
    prefix: str,
    *,
    save_json: bool = True,
    save_csv: bool = True,
) -> dict[str, str]:
    """Save per-run JSON and append one row to the shared results/results.csv."""
    destination = Path(output_dir).expanduser().resolve()
    destination.mkdir(parents=True, exist_ok=True)
    saved: dict[str, str] = {}

    if save_json:
        json_path = destination / f"{prefix}_analysis.json"
        with json_path.open("w", encoding="utf-8") as handle:
            json.dump(results, handle, indent=2, ensure_ascii=False, allow_nan=False)
        saved["json"] = str(json_path)

    if save_csv:
        csv_path = _append_shared_csv(results, destination, prefix)
        saved["csv"] = str(csv_path)

    return saved


def _cleanup_incomplete_outputs(output_dir: str | Path, prefix: str) -> list[str]:
    """Remove only per-run files bearing the current unique prefix."""
    destination = Path(output_dir).expanduser().resolve()
    if not destination.exists() or not destination.is_dir():
        return []
    removed: list[str] = []
    for path in destination.glob(f"{prefix}_*"):
        if path.is_file():
            path.unlink()
            removed.append(str(path))
    return removed


def _technical_failure_results(
    audio_file: str | Path,
    error: BaseException,
    category: str,
    settings_path: str | Path,
) -> dict[str, Any]:
    path = Path(audio_file).expanduser().resolve()
    file_size = path.stat().st_size if path.exists() and path.is_file() else None
    detail = str(error).strip() or type(error).__name__
    return {
        "file_information": {
            "file_path": str(path),
            "file_size_bytes": file_size,
        },
        "analysis_information": {
            "analysis_status": "technical_failure",
            "settings_file": str(Path(settings_path).expanduser().resolve()),
        },
        "error": {
            "category": category,
            "type": type(error).__name__,
            "message": detail,
        },
        "quality_assessment": {
            "status": "not_evaluated",
            "warnings": [],
            "failures": [],
        },
    }


def _record_technical_failure(
    audio_file: str | Path,
    output_dir: str | Path,
    prefix: str,
    error: BaseException,
    category: str,
    settings_path: str | Path,
) -> Path:
    destination = Path(output_dir).expanduser().resolve()
    destination.mkdir(parents=True, exist_ok=True)
    record = _technical_failure_results(audio_file, error, category, settings_path)
    return _append_shared_csv(record, destination, prefix)


def create_visualizations(
    context: AnalysisContext,
    results: dict[str, Any],
    output_dir: str | Path,
    prefix: str,
) -> dict[str, str]:
    """Create the six requested Matplotlib visualizations."""
    destination = Path(output_dir).expanduser().resolve()
    destination.mkdir(parents=True, exist_ok=True)
    saved: dict[str, str] = {}

    def save_figure(name: str) -> None:
        path = destination / f"{prefix}_{name}.png"
        plt.tight_layout()
        plt.savefig(path, dpi=160, bbox_inches="tight")
        plt.close()
        saved[name] = str(path)

    plt.figure(figsize=(12, 4))
    librosa.display.waveshow(context.audio, sr=context.sample_rate, alpha=0.8)
    plt.title("Audio waveform")
    plt.xlabel("Time (s)")
    plt.ylabel("Amplitude (full scale)")
    plt.grid(alpha=0.2)
    save_figure("waveform")

    spectrogram_db = librosa.power_to_db(context.power, ref=np.max, top_db=80.0)
    plt.figure(figsize=(12, 5))
    librosa.display.specshow(
        spectrogram_db,
        sr=context.sample_rate,
        hop_length=context.config.hop_length,
        n_fft=context.config.frame_length,
        x_axis="time",
        y_axis="log",
    )
    plt.colorbar(format="%+2.0f dB")
    plt.title("Log-frequency spectrogram")
    save_figure("spectrogram")

    nperseg = min(context.config.frame_length, context.audio.size)
    spectrum_frequencies, spectrum_power = welch(
        context.audio,
        fs=context.sample_rate,
        window="hann",
        nperseg=nperseg,
        noverlap=min(nperseg // 2, nperseg - 1),
        scaling="density",
    )
    spectrum_db = 10.0 * np.log10(np.maximum(spectrum_power, EPSILON))
    plt.figure(figsize=(12, 4))
    plt.semilogx(np.maximum(spectrum_frequencies, 1.0), spectrum_db)
    plt.title("Welch frequency spectrum")
    plt.xlabel("Frequency (Hz)")
    plt.ylabel("Power spectral density (dBFS/Hz)")
    plt.grid(which="both", alpha=0.25)
    save_figure("frequency_spectrum")

    rms_dbfs = librosa.amplitude_to_db(
        np.maximum(context.frame_rms, EPSILON), ref=1.0, top_db=None
    )
    plt.figure(figsize=(12, 4))
    plt.plot(context.frame_times, rms_dbfs, linewidth=1.1)
    plt.scatter(
        context.frame_times[~context.active_frames],
        rms_dbfs[~context.active_frames],
        s=8,
        color="gray",
        label="Ignored silent frames",
    )
    plt.title("RMS loudness over time")
    plt.xlabel("Time (s)")
    plt.ylabel("RMS level (dBFS)")
    if np.any(~context.active_frames):
        plt.legend()
    plt.grid(alpha=0.25)
    save_figure("rms_loudness")

    plt.figure(figsize=(12, 4))
    plt.plot(context.frame_times, context.flatness, linewidth=1.1)
    plt.ylim(0.0, 1.0)
    plt.title("Spectral flatness over time")
    plt.xlabel("Time (s)")
    plt.ylabel("Spectral flatness")
    plt.grid(alpha=0.25)
    save_figure("spectral_flatness")

    labels = ["Bass", "Treble"]
    values = [results["bass"]["energy_percentage"], results["treble"]["energy_percentage"]]
    plt.figure(figsize=(7, 4))
    bars = plt.bar(labels, values, color=["#3566b8", "#d17432"])
    plt.bar_label(bars, fmt="%.2f%%", padding=3)
    plt.title("Bass and treble energy comparison")
    plt.ylabel("Percentage of total active-frame spectral energy")
    plt.ylim(0.0, max(5.0, max(values) * 1.2))
    plt.grid(axis="y", alpha=0.25)
    save_figure("band_energy_comparison")

    return saved


def print_report(results: dict[str, Any], saved_files: dict[str, str] | None = None) -> None:
    """Print a concise, readable terminal report."""
    info = results["file_information"]
    analysis = results["analysis_information"]
    loudness = results["loudness"]
    print("\nAudio quality analysis")
    print("=" * 72)
    print(f"File:       {info['file_path']}")
    print(f"Format:     {info.get('container_format', 'decoder-dependent')}")
    print(f"Sample rate:{info['sample_rate']:>10,d} Hz")
    print(f"Duration:   {info['duration_seconds']:>10.3f} s")
    if info.get("decode_status") != "complete":
        print(f"Recovery:   {info['decode_status']}")
        print(f"Warning:    {info['recovery_warning']}")
    print(
        f"Frames:     {analysis['analyzed_frame_count']} analyzed, "
        f"{analysis['ignored_silent_frame_count']} silent/near-silent ignored"
    )
    print("-" * 72)
    print(
        f"Bass:       RMS {results['bass']['rms']:.6f}, "
        f"energy {results['bass']['energy_percentage']:.2f}%"
    )
    print(
        f"Treble:     RMS {results['treble']['rms']:.6f}, "
        f"energy {results['treble']['energy_percentage']:.2f}%"
    )
    print(
        "Loudness:   mean {mean_dbfs:.2f}, median {median_dbfs:.2f}, "
        "min {minimum_dbfs:.2f}, max {maximum_dbfs:.2f}, std {standard_deviation_db:.2f} dB".format(
            **loudness
        )
    )
    print(
        f"Flatness:   mean {results['flatness']['mean']:.5f}, "
        f"std {results['flatness']['standard_deviation']:.5f}"
    )
    print(f"Sharpness:  {results['sharpness']['normalized_score']:.5f} (approximate, 0-1)")
    print(
        f"Noise:      RMS {results['noise']['noise_rms']:.6f}, "
        f"{results['noise']['noise_dbfs']:.2f} dBFS, "
        f"estimated SNR {results['noise']['estimated_snr_db']:.2f} dB"
    )
    print(f"Noise note: {results['noise']['reliability_warning']}")
    print(
        f"Distortion: {results['distortion']['estimated_score']:.2f}/100 heuristic risk, "
        f"samples clipped {results['distortion']['clipped_sample_percentage']:.4f}%, "
        f"frames clipped {results['distortion']['clipped_frame_percentage']:.2f}%"
    )
    print(f"              {results['distortion']['interpretation']}")
    quality = results.get("quality_assessment", {})
    if quality:
        print(f"Quality:    {str(quality.get('status', 'not_evaluated')).upper()}")
        for message in quality.get("failures", []):
            print(f"  Failure:  {message}")
        for message in quality.get("warnings", []):
            print(f"  Warning:  {message}")
    if saved_files:
        print("-" * 72)
        print("Saved files:")
        for label, path in saved_files.items():
            print(f"  {label}: {path}")


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Extract audio features and no-reference quality estimates.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("audio_file", nargs="?", help="WAV, MP3, FLAC, or OGG file")
    parser.add_argument("--output-dir", default="results", help="Directory for generated files")
    parser.add_argument(
        "--settings",
        default=str(DEFAULT_SETTINGS_PATH),
        help="Versioned JSON settings file",
    )
    parser.add_argument("--frame-length", type=int, default=None, help="Override STFT/RMS frame size")
    parser.add_argument("--hop-length", type=int, default=None, help="Override samples between frames")
    parser.add_argument(
        "--noise-percentile",
        type=float,
        default=None,
        help="Override lowest RMS percentile used as noise",
    )
    parser.add_argument(
        "--clipping-threshold",
        type=float,
        default=None,
        help="Override absolute full-scale clipping threshold",
    )
    parser.add_argument(
        "--bass-max-frequency",
        type=float,
        default=None,
        help="Override upper bass-band frequency in Hz",
    )
    parser.add_argument(
        "--treble-min-frequency",
        type=float,
        default=None,
        help="Override lower treble-band frequency in Hz",
    )
    parser.add_argument(
        "--save-plots", action=argparse.BooleanOptionalAction, default=True, help="Save six PNG plots"
    )
    parser.add_argument(
        "--save-json", action=argparse.BooleanOptionalAction, default=True, help="Save nested JSON results"
    )
    parser.add_argument(
        "--save-csv",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Append one row to the shared results/results.csv file",
    )
    return parser


def _config_with_cli_overrides(base: AnalyzerConfig, args: argparse.Namespace) -> AnalyzerConfig:
    overrides = {
        "frame_length": args.frame_length,
        "hop_length": args.hop_length,
        "noise_percentile": args.noise_percentile,
        "clipping_threshold": args.clipping_threshold,
        "bass_max_frequency": args.bass_max_frequency,
        "treble_min_frequency": args.treble_min_frequency,
    }
    return replace(base, **{name: value for name, value in overrides.items() if value is not None})


def main(argv: Sequence[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    audio_file = args.audio_file
    if not audio_file:
        try:
            audio_file = input("Audio file path: ").strip().strip('"')
        except EOFError:
            audio_file = ""
    if not audio_file:
        print("Error: an audio file path is required.", file=sys.stderr)
        return 2

    prefix = _unique_prefix(audio_file)
    behavior = FailureBehavior()
    settings_path = args.settings

    def handle_technical_failure(
        error: BaseException,
        category: str,
        exit_code: int,
        label: str,
    ) -> int:
        plt.close("all")
        if behavior.cleanup_incomplete_outputs:
            try:
                removed = _cleanup_incomplete_outputs(args.output_dir, prefix)
                if removed:
                    print(f"Cleaned {len(removed)} incomplete output file(s).", file=sys.stderr)
            except OSError as cleanup_error:
                print(f"Warning: incomplete output cleanup failed: {cleanup_error}", file=sys.stderr)
        if behavior.record_technical_failures_in_csv:
            try:
                failure_csv = _record_technical_failure(
                    audio_file,
                    args.output_dir,
                    prefix,
                    error,
                    category,
                    settings_path,
                )
                print(f"Failure recorded in: {failure_csv}", file=sys.stderr)
            except Exception as record_error:
                print(f"Warning: failure record could not be saved: {record_error}", file=sys.stderr)
        detail = str(error).strip() or type(error).__name__
        print(f"{label}: {detail}", file=sys.stderr)
        return exit_code

    try:
        settings = load_settings(settings_path)
        behavior = settings.failure_behavior
        config = _config_with_cli_overrides(settings.analysis, args)
        _validate_config(config)
        print(f"Analyzing: {Path(audio_file).expanduser()}", flush=True)
        print(f"Settings:  {settings.settings_path}", flush=True)
        print("Please wait; long recordings and plot generation may take a minute.", flush=True)
        results, context = _analyze_with_context(audio_file, config, settings.safety)
        results["analysis_information"]["analysis_status"] = "completed"
        results["analysis_information"]["settings_file"] = str(settings.settings_path)
        results["analysis_information"]["settings_snapshot"] = {
            "analysis": asdict(config),
            "safety": asdict(settings.safety),
            "quality_thresholds": asdict(settings.quality_thresholds),
            "failure_behavior": asdict(settings.failure_behavior),
        }
        results["quality_assessment"] = evaluate_quality(
            results,
            settings.quality_thresholds,
        )
        quality_failed = results["quality_assessment"]["status"] == "failed"
        save_quality_outputs = (
            not quality_failed or behavior.save_outputs_on_quality_failure
        )
        print("Feature extraction complete. Saving numerical results...", flush=True)
        saved = save_results(
            results,
            args.output_dir,
            prefix,
            save_json=args.save_json and save_quality_outputs,
            save_csv=args.save_csv,
        )
        if args.save_plots and save_quality_outputs:
            print("Creating six visualizations...", flush=True)
            saved.update(create_visualizations(context, results, args.output_dir, prefix))
        print_report(results, saved)
        if quality_failed:
            print(
                f"Analysis completed, but configured quality thresholds failed "
                f"(exit code {behavior.quality_failure_exit_code}).",
                file=sys.stderr,
            )
            return behavior.quality_failure_exit_code
        return 0
    except AudioAnalysisError as exc:
        return handle_technical_failure(exc, "input_or_configuration", 2, "Audio analysis error")
    except MemoryError as exc:
        return handle_technical_failure(
            exc,
            "resource_limit",
            1,
            "Audio analysis ran out of memory",
        )
    except (OSError, RuntimeError) as exc:
        return handle_technical_failure(exc, "processing_or_output", 1, "Output or processing error")
    except KeyboardInterrupt as exc:
        return handle_technical_failure(exc, "cancelled", 130, "Audio analysis cancelled")
    except Exception as exc:
        return handle_technical_failure(exc, "unexpected", 1, "Unexpected audio analysis error")


if __name__ == "__main__":
    raise SystemExit(main())
