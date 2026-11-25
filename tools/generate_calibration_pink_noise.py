"""Generate the identical reference WAV for the app and external playback."""

from pathlib import Path
import wave

import numpy as np


def pink_noise(sample_rate=44100, seconds=30):
    size = sample_rate * seconds
    white = np.random.default_rng(20261125).standard_normal(size)
    spectrum = np.fft.rfft(white)
    frequencies = np.fft.rfftfreq(size, 1 / sample_rate)
    keep = (frequencies >= 40) & (frequencies <= 16000)
    spectrum[~keep] = 0
    spectrum[keep] /= np.sqrt(frequencies[keep])
    audio = np.fft.irfft(spectrum, n=size)
    fade = np.linspace(0, 1, sample_rate // 2)
    audio[:fade.size] *= fade
    audio[-fade.size:] *= fade[::-1]
    return audio * (0.1 / np.sqrt(np.mean(audio ** 2)))


def main():
    root = Path(__file__).resolve().parents[1]
    pcm = np.rint(pink_noise() * 32768).astype("<i2")
    for folder in ("frontend/assets/calibration", "docs/calibration"):
        directory = root / folder
        directory.mkdir(parents=True, exist_ok=True)
        with wave.open(str(directory / "karaok_pink_noise_30s.wav"), "wb") as wav:
            wav.setparams((1, 2, 44100, 0, "NONE", "not compressed"))
            wav.writeframes(pcm.tobytes())


if __name__ == "__main__":
    main()
