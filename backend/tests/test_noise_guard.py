import unittest

import numpy as np

from audio_engine.noise_guard import NoiseGuardConfig, apply_noise_guard
from tests.noise_fixtures import chicken_bursts, engine_noise, mix_at_mnr, music_like


SAMPLE_RATE = 44100
FRAME_LENGTH = 2048
HOP_LENGTH = 512


def guard(audio, preroll_seconds):
    return apply_noise_guard(
        audio, SAMPLE_RATE, preroll_seconds, NoiseGuardConfig(), FRAME_LENGTH, HOP_LENGTH
    )


def bass_db(audio):
    power = np.abs(np.fft.rfft(audio)) ** 2
    frequencies = np.fft.rfftfreq(audio.size, 1 / SAMPLE_RATE)
    return 10 * np.log10(power[frequencies <= 250].sum())


class NoiseGuardTests(unittest.TestCase):
    def test_split_removes_preroll_from_returned_audio(self):
        noise = engine_noise(SAMPLE_RATE, 3, 1)
        song = music_like(SAMPLE_RATE, 12, 2)
        result = guard(np.concatenate([noise, song + engine_noise(SAMPLE_RATE, 12, 3)]), 3.0)

        self.assertAlmostEqual(result.audio.size / SAMPLE_RATE, 12.0, places=1)
        self.assertTrue(result.report["subtraction_applied"])

    def test_subtraction_reduces_steady_noise_band_energy(self):
        song = music_like(SAMPLE_RATE, 12, 2)
        noise = engine_noise(SAMPLE_RATE, 12, 3)
        mixture = mix_at_mnr(song, noise, 10)
        noise_gain = np.linalg.norm(mixture - song) / np.linalg.norm(noise)
        preroll = engine_noise(SAMPLE_RATE, 3, 1) * noise_gain

        result = guard(np.concatenate([preroll, mixture]), 3.0)

        clean_bass = bass_db(song)
        self.assertGreater(abs(bass_db(mixture) - clean_bass), 1.0)
        self.assertLess(abs(bass_db(result.audio) - clean_bass), 1.0)

    def test_transient_frames_dropped(self):
        song = music_like(SAMPLE_RATE, 12, 2)
        bursts = chicken_bursts(SAMPLE_RATE, 12, 3)
        result = guard(mix_at_mnr(song, bursts, 10), 0.0)
        starts = np.arange(0, song.size - FRAME_LENGTH + 1, HOP_LENGTH)
        active_samples = np.flatnonzero(bursts)
        burst_frames = (
            np.searchsorted(active_samples, starts + FRAME_LENGTH)
            > np.searchsorted(active_samples, starts)
        )

        self.assertEqual(result.keep_frames.shape, burst_frames.shape)
        self.assertEqual(result.keep_frames.dtype, np.bool_)
        self.assertGreaterEqual((~result.keep_frames[burst_frames]).mean(), 0.80)
        self.assertLessEqual((~result.keep_frames[~burst_frames]).mean(), 0.05)

    def test_no_preroll_skips_subtraction_and_caps_confidence(self):
        song = music_like(SAMPLE_RATE, 12, 2)
        result = guard(song, 0.0)

        self.assertFalse(result.report["subtraction_applied"])
        self.assertIn(result.report["confidence"], ("medium", "low"))

    def test_silent_preroll_is_treated_as_missing(self):
        audio = np.concatenate([np.zeros(3 * SAMPLE_RATE), music_like(SAMPLE_RATE, 12, 2)])
        result = guard(audio, 3.0)

        self.assertFalse(result.report["subtraction_applied"])
        self.assertEqual(result.report["preroll_usable_seconds"], 0.0)

    def test_clean_music_is_left_nearly_unchanged(self):
        rng = np.random.default_rng(4)
        quiet = rng.standard_normal(3 * SAMPLE_RATE) * 10 ** (-80 / 20)
        song = music_like(SAMPLE_RATE, 12, 2)

        result = guard(np.concatenate([quiet, song]), 3.0)

        rms_db_change = 20 * np.log10(np.linalg.norm(result.audio) / np.linalg.norm(song))
        self.assertLess(abs(rms_db_change), 0.2)
        self.assertGreaterEqual(result.report["usable_percentage"], 95)
        self.assertEqual(result.report["confidence"], "high")
