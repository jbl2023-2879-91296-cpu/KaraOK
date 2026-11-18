import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

import numpy as np
import soundfile as sf

from audio_engine.analyzer import (
    AudioAnalysisError,
    SafetyLimits,
    _analyze_with_context,
    analyze_audio,
    load_settings,
    main,
)
from audio_engine.noise_guard import NoiseGuardConfig
from tests.noise_fixtures import engine_noise, music_like


SAMPLE_RATE = 44100


def noisy_song():
    song = 0.10 * music_like(SAMPLE_RATE, 12, 2)
    rng = np.random.default_rng(5)
    time = np.arange(song.size) / SAMPLE_RATE
    envelope = (time % 0.10 < 0.035) * (0.65 + 0.35 * np.sin(2 * np.pi * 160 * time))
    return song + 0.65 * envelope * rng.uniform(-1.0, 1.0, song.size)


class NoiseGuardAnalyzerTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.directory = Path(directory.name)

    def write_wav(self, song, preroll=None):
        path = self.directory / "recording.wav"
        audio = song if preroll is None else np.concatenate([preroll, song])
        sf.write(path, audio, SAMPLE_RATE, subtype="FLOAT")
        return path

    def write_settings(self, **noise_guard):
        path = self.directory / "settings.json"
        path.write_text(json.dumps({"schema_version": 1, "noise_guard": noise_guard}))
        return path

    def test_settings_rejects_unknown_noise_guard_key(self):
        path = self.write_settings(unknown=True)
        with self.assertRaisesRegex(AudioAnalysisError, "Unknown setting.*'noise_guard': unknown"):
            load_settings(path)

    def test_settings_validate_usable_percentages(self):
        path = self.write_settings(usable_fail_percentage=60, usable_warn_percentage=60)
        with self.assertRaisesRegex(AudioAnalysisError, "usable_fail_percentage"):
            load_settings(path)

    def test_settings_reject_invalid_noise_guard_values(self):
        for name, value in [
            ("transient_window_seconds", "bad"),
            ("transient_window_seconds", 0),
            ("transient_band_fraction", 2),
            ("transient_band_fraction", True),
            ("transient_band_db", float("inf")),
            ("preroll_silence_dbfs", float("nan")),
            ("subtraction_floor", -0.1),
            ("transient_pad_frames", 1.5),
            ("transient_pad_frames", -1),
            ("mnr_low_db", 11),
        ]:
            with self.subTest(name=name, value=value):
                with self.assertRaisesRegex(AudioAnalysisError, name):
                    load_settings(self.write_settings(**{name: value}))

    def test_cli_preroll_flag_reaches_analysis(self):
        path = self.write_wav(music_like(SAMPLE_RATE, 12, 2), engine_noise(SAMPLE_RATE, 3, 1))
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            self.assertEqual(main([
                str(path), "--noise-preroll-seconds", "3", "--output-dir", str(self.directory),
                "--no-save-plots", "--no-save-csv",
            ]), 0)
        output, = self.directory.glob("*_analysis.json")
        self.assertEqual(json.loads(output.read_text(encoding="utf-8"))["noise_guard"]["preroll_seconds"], 3.0)

    def test_short_song_after_preroll_raises(self):
        path = self.write_wav(music_like(SAMPLE_RATE, 9, 2), engine_noise(SAMPLE_RATE, 3, 1))
        with self.assertRaisesRegex(
            AudioAnalysisError, r"^Record at least 10 seconds of song after the noise check\.$"
        ):
            analyze_audio(path, noise_preroll_seconds=3.0)

    def test_ten_second_song_after_preroll_is_accepted(self):
        path = self.write_wav(music_like(SAMPLE_RATE, 10, 2), engine_noise(SAMPLE_RATE, 3, 1))
        result = analyze_audio(path, noise_preroll_seconds=3.0)
        self.assertEqual(result["noise_guard"]["preroll_seconds"], 3.0)

    def test_song_started_during_preroll_skips_subtraction(self):
        song = music_like(SAMPLE_RATE, 15, 2)
        path = self.write_wav(song[3 * SAMPLE_RATE:], song[:3 * SAMPLE_RATE])
        result = analyze_audio(path, noise_preroll_seconds=3.0)
        self.assertIs(result["noise_guard"]["subtraction_applied"], False)
        self.assertIn(
            "The song started during the noise check, so background noise was not removed.",
            result["noise_guard"]["warnings"],
        )
        self.assertEqual(result["noise"]["source"], "quiet_frame_estimate")

    def test_mostly_noise_recording_fails_quality_without_crashing(self):
        path = self.write_wav(noisy_song())
        result = analyze_audio(path, safety=SafetyLimits(minimum_active_frames=250))
        self.assertLess(result["noise_guard"]["usable_percentage"], 30.0)
        quality = result["quality_assessment"]
        self.assertEqual(quality["status"], "failed")
        self.assertTrue(any(reason.startswith("Too noisy") for reason in quality["failures"]))
        self.assertLess(result["analysis_information"]["analyzed_frame_count"], 250)
        self.assertTrue(quality["warnings"])

    def test_zero_active_frames_label_ungated_diagnostics(self):
        path = self.write_wav(noisy_song())
        settings = self.write_settings(transient_pad_frames=1000)
        stdout = io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(io.StringIO()):
            self.assertEqual(main([
                str(path), "--settings", str(settings), "--output-dir", str(self.directory),
                "--no-save-csv",
            ]), 3)
        output, = self.directory.glob("*_analysis.json")
        result = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(result["analysis_information"]["analyzed_frame_count"], 0)
        for section in ("bass", "treble", "loudness", "flatness", "sharpness", "noise", "distortion"):
            with self.subTest(section=section):
                self.assertEqual(result[section].get("frame_metric_source"), "ungated_diagnostic")
        self.assertIsNone(result["loudness"]["integrated_lufs"])
        self.assertIn("Ungated diagnostic values", stdout.getvalue())
        self.assertEqual(len(list(self.directory.glob("*.png"))), 6)

    def test_preroll_sets_reliable_noise_level(self):
        path = self.write_wav(music_like(SAMPLE_RATE, 12, 2), engine_noise(SAMPLE_RATE, 3, 1))
        result = analyze_audio(path, noise_preroll_seconds=3.0)
        self.assertIs(result["noise"]["reliable"], True)
        self.assertEqual(result["noise"]["source"], "preroll")
        self.assertEqual(result["noise"]["noise_dbfs"], result["noise_guard"]["preroll_noise_dbfs"])

    def test_zero_preroll_matches_previous_metrics(self):
        path = self.write_wav(music_like(SAMPLE_RATE, 12, 2))
        guarded, _ = _analyze_with_context(path, noise_preroll_seconds=0.0)
        previous, _ = _analyze_with_context(path, noise_guard=NoiseGuardConfig(enabled=False))
        for section, metric in [
            ("bass", "energy_percentage"), ("treble", "energy_percentage"),
            ("flatness", "mean"), ("sharpness", "normalized_score"), ("loudness", "integrated_lufs"),
        ]:
            with self.subTest(section=section):
                self.assertAlmostEqual(guarded[section][metric], previous[section][metric], delta=1e-6)
