"""Remove steady noise and identify frames with sudden background noise."""

from dataclasses import dataclass
from typing import Any

import librosa
import numpy as np
from scipy.ndimage import binary_dilation, median_filter


_EPS = 1e-12


@dataclass(frozen=True)
class NoiseGuardConfig:
    enabled: bool = True
    preroll_min_usable_seconds: float = 1.0
    preroll_silence_dbfs: float = -90.0
    subtraction_floor: float = 0.1
    music_in_preroll_margin_db: float = 6.0
    transient_window_seconds: float = 1.5
    transient_band_db: float = 6.0
    transient_band_fraction: float = 0.3
    transient_pad_frames: int = 2
    usable_warn_percentage: float = 60.0
    usable_fail_percentage: float = 30.0
    mnr_warn_db: float = 10.0
    mnr_low_db: float = 5.0


@dataclass
class NoiseGuardResult:
    audio: np.ndarray
    keep_frames: np.ndarray
    report: dict[str, Any]


def _preroll_profile(
    preroll: np.ndarray,
    sample_rate: int,
    config: NoiseGuardConfig,
    frame_length: int,
    hop_length: int,
) -> tuple[float, float | None, np.ndarray | None]:
    if preroll.size < frame_length:
        return 0.0, None, None

    frames = librosa.util.frame(preroll, frame_length=frame_length, hop_length=hop_length)
    frame_power = np.mean(np.square(frames), axis=0)
    usable = frame_power > 10 ** (config.preroll_silence_dbfs / 10)
    starts = np.flatnonzero(usable) * hop_length
    if not starts.size:
        return 0.0, None, None

    # Count the union of usable frames without counting overlapping samples twice.
    usable_samples = frame_length + np.minimum(np.diff(starts), frame_length).sum()
    usable_seconds = float(usable_samples / sample_rate)
    if usable_seconds < config.preroll_min_usable_seconds:
        return usable_seconds, None, None

    spectrum = librosa.stft(
        preroll, n_fft=frame_length, hop_length=hop_length, window="hann", center=False
    )
    profile = np.mean(np.abs(spectrum[:, usable]) ** 2, axis=1)
    return usable_seconds, float(frame_power[usable].mean()), profile


def _subtract_noise(
    song: np.ndarray,
    noise_profile: np.ndarray,
    subtraction_floor: float,
    frame_length: int,
    hop_length: int,
) -> np.ndarray:
    # Center padding lets the inverse transform reconstruct both song endpoints.
    spectrum = librosa.stft(
        song, n_fft=frame_length, hop_length=hop_length, window="hann", center=True
    )
    power = np.maximum(np.abs(spectrum) ** 2, _EPS)
    gain = np.sqrt(np.maximum(1 - noise_profile[:, None] / power, subtraction_floor ** 2))
    return librosa.istft(
        spectrum * gain,
        n_fft=frame_length,
        hop_length=hop_length,
        window="hann",
        center=True,
        length=song.size,
    )


def _keep_frames(
    audio: np.ndarray,
    sample_rate: int,
    config: NoiseGuardConfig,
    frame_length: int,
    hop_length: int,
) -> np.ndarray:
    frame_count = max(0, 1 + (audio.size - frame_length) // hop_length)
    if not config.enabled or not frame_count or sample_rate <= 120:
        return np.ones(frame_count, dtype=bool)

    spectrum = librosa.stft(
        audio, n_fft=frame_length, hop_length=hop_length, window="hann", center=False
    )
    power = np.abs(spectrum) ** 2
    frequencies = librosa.fft_frequencies(sr=sample_rate, n_fft=frame_length)
    edges = np.geomspace(60, min(16000, sample_rate / 2), 25)
    boundaries = np.searchsorted(frequencies, edges)
    boundaries[-1] = np.searchsorted(frequencies, edges[-1], side="right")
    band_power = np.stack(
        [power[lower:upper].sum(axis=0) for lower, upper in zip(boundaries[:-1], boundaries[1:])]
    )
    # Normalize before the log floor so it is relative to full scale.
    band_db = 10 * np.log10(np.maximum(band_power / frame_length ** 2, _EPS))
    window_frames = max(1, round(config.transient_window_seconds * sample_rate / hop_length))
    median_db = median_filter(band_db, size=(1, window_frames), mode="nearest")
    excess = band_db - median_db
    bad = (excess > config.transient_band_db).mean(axis=0) >= config.transient_band_fraction
    if config.transient_pad_frames > 0:
        bad = binary_dilation(bad, iterations=config.transient_pad_frames)
    return ~bad


def apply_noise_guard(
    audio: np.ndarray,
    sample_rate: int,
    preroll_seconds: float,
    config: NoiseGuardConfig,
    frame_length: int,
    hop_length: int,
) -> NoiseGuardResult:
    """Split off the noise check, clean the song, and return the analyzer's frame mask."""
    preroll_samples = min(audio.size, max(0, round(preroll_seconds * sample_rate)))
    preroll = audio[:preroll_samples]
    song = audio[preroll_samples:]
    warnings = []
    usable_seconds = 0.0
    noise_dbfs = None
    music_to_noise_db = None
    subtraction_applied = False

    if config.enabled:
        usable_seconds, noise_power, noise_profile = _preroll_profile(
            preroll, sample_rate, config, frame_length, hop_length
        )
        if noise_profile is None:
            warnings.append(
                "No background-noise check was recorded, so steady noise was not removed."
            )
        elif song.size:
            song_power = float(np.mean(np.square(song)))
            preroll_margin_db = 10 * np.log10(max(song_power, _EPS) / noise_power)
            if preroll_margin_db < config.music_in_preroll_margin_db:
                warnings.append(
                    "The song started during the noise check, so background noise was not removed."
                )
            else:
                noise_dbfs = float(10 * np.log10(noise_power))
                music_to_noise_db = float(
                    10 * np.log10(max(song_power - noise_power, _EPS) / noise_power)
                )
                if song.size >= frame_length:
                    song = _subtract_noise(
                        song, noise_profile, config.subtraction_floor, frame_length, hop_length
                    )
                    subtraction_applied = True

    keep = _keep_frames(song, sample_rate, config, frame_length, hop_length)
    usable_percentage = float(100 * keep.mean()) if keep.size else 0.0
    removed_percentage = 100.0 - usable_percentage if keep.size else 0.0
    if music_to_noise_db is not None and music_to_noise_db < config.mnr_warn_db:
        warnings.append(
            "Background noise is loud compared with the song. Move the phone closer to the speaker."
        )
    if removed_percentage >= 10:
        warnings.append(f"{removed_percentage:.0f}% of the recording had sudden noises and was skipped.")

    confidence = "medium"
    if usable_percentage < config.usable_warn_percentage or (
        music_to_noise_db is not None and music_to_noise_db < config.mnr_low_db
    ):
        confidence = "low"
    elif music_to_noise_db is not None and music_to_noise_db >= config.mnr_warn_db:
        confidence = "high"

    return NoiseGuardResult(song, keep, {
        "preroll_seconds": float(preroll_seconds),
        "preroll_usable_seconds": usable_seconds,
        "preroll_noise_dbfs": noise_dbfs,
        "music_to_noise_db": music_to_noise_db,
        "subtraction_applied": subtraction_applied,
        "transient_frames_removed_percentage": removed_percentage,
        "usable_percentage": usable_percentage,
        "confidence": confidence,
        "warnings": warnings,
    })
