"""Deterministic synthetic song and background noise for analysis tests."""

import numpy as np
from scipy import signal


def music_like(sr: int, seconds: float, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    time = np.arange(round(sr * seconds)) / sr
    bass_notes = np.array([55.0, 73.42, 82.41, 110.0])
    beats = 2 * time
    note = beats.astype(int) % bass_notes.size
    transition = np.clip((beats % 1 - 0.8) / 0.2, 0, 1)
    glide = 0.5 - 0.5 * np.cos(np.pi * transition)
    next_note = bass_notes[(note + 1) % bass_notes.size]
    bass_frequency = bass_notes[note] + (next_note - bass_notes[note]) * glide
    bass_phase = 2 * np.pi * np.cumsum(bass_frequency) / sr
    music = 0.23 * np.sin(bass_phase)

    for frequency in (261.63, 329.63, 392, 523.25, 659.25, 783.99, 1046.5, 1567.98, 1975.53):
        phase = rng.uniform(0, 2 * np.pi)
        music += 0.18 * np.sin(2 * np.pi * frequency * time + phase)
    music *= 0.88 + 0.12 * np.cos(2 * np.pi * 2 * time)

    if sr > 12800:
        hat_spectrum = np.fft.rfft(rng.standard_normal(time.size))
        frequencies = np.fft.rfftfreq(time.size, 1 / sr)
        hat_spectrum[(frequencies < 6400) | (frequencies > 9600)] = 0
        hat = np.fft.irfft(hat_spectrum, n=time.size)
        hat_envelope = np.exp(3 * (np.cos(2 * np.pi * 4 * time) - 1))
        music += 0.024 * hat * hat_envelope
    return 0.5 * music / np.max(np.abs(music))


def engine_noise(sr: int, seconds: float, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    time = np.arange(round(sr * seconds)) / sr
    noise = sum(
        np.sin(2 * np.pi * 35 * harmonic * time + rng.uniform(0, 2 * np.pi)) / harmonic
        for harmonic in range(1, 7)
    )
    brown = signal.lfilter(
        [1.0], [1.0, -np.exp(-2 * np.pi * 15 / sr)], rng.standard_normal(time.size)
    )
    noise += 0.08 * brown / np.std(brown)
    return noise * 0.045


def chicken_bursts(sr: int, seconds: float, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    bursts = np.zeros(round(sr * seconds))
    burst_length = round(0.15 * sr)
    time = np.arange(burst_length) / sr
    fade = np.minimum(np.minimum(time / 0.020, (0.15 - time) / 0.020), 1.0)
    envelope = 0.5 - 0.5 * np.cos(np.pi * fade)
    start_seconds = rng.uniform(0.5, 1.0)
    while start_seconds + 0.15 <= seconds:
        start = round(start_seconds * sr)
        frequency = 2750 + 1220 * np.sin(2 * np.pi * rng.uniform(35, 47) * time)
        phase = 2 * np.pi * np.cumsum(frequency) / sr
        burst = np.zeros(burst_length)
        for harmonic in range(1, min(8, (sr - 1) // 8000) + 1):
            burst += np.sin(harmonic * phase) / harmonic
        bursts[start : start + burst_length] += envelope * burst
        start_seconds += rng.uniform(0.75, 1.25)
    return bursts


def babble(sr: int, seconds: float, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    time = np.arange(round(sr * seconds)) / sr
    frequencies = np.fft.rfftfreq(time.size, 1 / sr)
    pink_gain = 1 / np.sqrt(np.maximum(frequencies, 1.0))
    babble_signal = np.zeros(time.size)
    for _ in range(4):
        pink = np.fft.irfft(np.fft.rfft(rng.standard_normal(time.size)) * pink_gain, n=time.size)
        talker = _bandpass(pink, sr, 240, 500)
        talker += _bandpass(pink, sr, 900, 1600)
        talker += _bandpass(pink, sr, 2300, 3300)
        phase = rng.uniform(0, 2 * np.pi)
        envelope = (0.5 + 0.5 * np.cos(2 * np.pi * rng.uniform(3.5, 4.5) * time + phase)) ** 2
        babble_signal += talker * envelope
    return babble_signal


def mix_at_mnr(music: np.ndarray, noise: np.ndarray, mnr_db: float) -> np.ndarray:
    gain = np.linalg.norm(music) / np.linalg.norm(noise) * 10 ** (-mnr_db / 20)
    return music + gain * noise


def _bandpass(audio: np.ndarray, sr: int, low: float, high: float) -> np.ndarray:
    coefficients = signal.butter(4, (low, high), "bandpass", fs=sr, output="sos")
    return signal.sosfilt(coefficients, audio)
