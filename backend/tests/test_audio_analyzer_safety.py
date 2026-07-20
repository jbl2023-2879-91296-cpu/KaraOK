import csv
import io
import json
import tempfile
import unittest
import warnings
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch

import numpy as np
import soundfile as sf

from audio_analyzer import (
    AnalyzerConfig,
    AudioAnalysisError,
    PhoneRecordingConfig,
    QualityThresholds,
    SafetyLimits,
    _analyze_with_context,
    _cleanup_incomplete_outputs,
    _record_technical_failure,
    create_visualizations,
    evaluate_quality,
    load_audio,
    load_settings,
    main,
    measure_phone_recording,
    save_results,
)


class AudioAnalyzerSafetyTests(unittest.TestCase):
    def test_default_settings_are_valid(self):
        settings = load_settings()

        self.assertEqual(settings.safety.maximum_file_size_mb, 100.0)
        self.assertEqual(settings.safety.maximum_duration_seconds, 900.0)
        self.assertEqual(settings.failure_behavior.quality_failure_exit_code, 3)
        self.assertEqual(settings.phone_recording.test_tone_frequency_hz, 1000.0)
        self.assertTrue(settings.phone_recording.require_lossless)
        self.assertEqual(settings.analysis.hpss_max_frames, 2048)

    def test_unknown_setting_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "settings.json"
            path.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "safety": {"maximum_file_sze_mb": 100.0},
                    }
                ),
                encoding="utf-8",
            )

            with self.assertRaisesRegex(AudioAnalysisError, "maximum_file_sze_mb"):
                load_settings(path)

    def test_quality_thresholds_produce_pass_warning_and_failure(self):
        thresholds = QualityThresholds()

        def result(snr: float, distortion: float = 10.0) -> dict:
            return {
                "noise": {"estimated_snr_db": snr},
                "distortion": {
                    "estimated_score": distortion,
                    "clipped_sample_percentage": 0.0,
                },
            }

        self.assertEqual(evaluate_quality(result(15.0), thresholds)["status"], "passed")
        self.assertEqual(evaluate_quality(result(7.0), thresholds)["status"], "warning")
        advisory_failure = evaluate_quality(result(4.0), thresholds)
        self.assertEqual(advisory_failure["status"], "warning")
        self.assertEqual(
            advisory_failure["measured"]["snr_threshold_enforcement"],
            "advisory_only",
        )

        controlled = result(4.0)
        controlled["phone_recording"] = {
            "noise": {"measured_program_to_noise_snr_db": 4.0}
        }
        controlled_failure = evaluate_quality(controlled, thresholds)
        self.assertEqual(controlled_failure["status"], "failed")
        self.assertEqual(
            controlled_failure["measured"]["snr_threshold_enforcement"],
            "enforced",
        )

    def test_file_size_is_rejected_before_decode(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "oversized.wav"
            path.write_bytes(b"0" * 1024)
            limits = SafetyLimits(maximum_file_size_mb=0.0001)

            with self.assertRaisesRegex(AudioAnalysisError, "configured maximum"):
                load_audio(path, limits)

    def test_shared_csv_appends_and_cleanup_is_prefix_scoped(self):
        with tempfile.TemporaryDirectory() as directory:
            results_root = Path(directory) / "results"
            output = results_root / "sample"
            record = {"file_information": {"file_path": "sample.wav"}}
            first = "sample_20260719T070000_000001Z"
            second = "sample_20260719T070001_000002Z"

            with warnings.catch_warnings():
                warnings.simplefilter("error", FutureWarning)
                save_results(record, output, first, save_json=False, save_csv=True)
                save_results(record, output, second, save_json=False, save_csv=True)
                _record_technical_failure(
                    "missing.wav",
                    output,
                    "missing_20260719T070002_000003Z",
                    AudioAnalysisError("missing input"),
                    "input_or_configuration",
                    "settings.json",
                )
            shared_csv = results_root / "results.csv"
            with shared_csv.open(encoding="utf-8", newline="") as source:
                rows = list(csv.DictReader(source))

            self.assertEqual(
                [row["analysis_id"] for row in rows],
                [first, second, "missing_20260719T070002_000003Z"],
            )
            self.assertEqual(rows[-1]["error.category"], "input_or_configuration")
            self.assertEqual(list(output.glob("*.csv")), [])

            first_file = output / f"{first}_analysis.json"
            other_file = output / f"{second}_analysis.json"
            first_file.write_text("{}", encoding="utf-8")
            other_file.write_text("{}", encoding="utf-8")
            removed = _cleanup_incomplete_outputs(output, first)

            self.assertEqual(removed, [str(first_file)])
            self.assertFalse(first_file.exists())
            self.assertTrue(other_file.exists())

    def test_controlled_phone_measurements_use_separate_noise_and_tone(self):
        sample_rate = 48_000
        duration_seconds = 5.0
        time = np.arange(int(sample_rate * duration_seconds), dtype=np.float64) / sample_rate
        random = np.random.default_rng(20260719)
        program = 0.1 * np.sin(2.0 * np.pi * 440.0 * time)
        noise = random.normal(0.0, 0.001, size=time.size)
        tone = 0.2 * np.sin(2.0 * np.pi * 1000.0 * time)
        tone += 0.002 * np.sin(2.0 * np.pi * 2000.0 * time)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            program_path = root / "program.wav"
            noise_path = root / "noise.wav"
            tone_path = root / "tone.wav"
            sf.write(program_path, program, sample_rate, subtype="PCM_24")
            sf.write(noise_path, noise, sample_rate, subtype="PCM_24")
            sf.write(tone_path, tone, sample_rate, subtype="PCM_24")

            _, context = _analyze_with_context(
                program_path,
                AnalyzerConfig(),
                SafetyLimits(),
            )
            measured = measure_phone_recording(
                program_path,
                context,
                noise_path,
                tone_path,
                PhoneRecordingConfig(),
                SafetyLimits(),
                reference_spl_db=80.0,
            )

        self.assertEqual(measured["mode"], "controlled_phone_recording")
        self.assertGreater(
            measured["noise"]["measured_program_to_noise_snr_db"],
            30.0,
        )
        self.assertAlmostEqual(
            measured["tone"]["detected_fundamental_hz"],
            1000.0,
            places=2,
        )
        self.assertAlmostEqual(
            measured["tone"]["end_to_end_thd_percent"],
            1.0,
            delta=0.15,
        )
        self.assertGreaterEqual(
            measured["tone"]["end_to_end_thdn_percent"],
            measured["tone"]["end_to_end_thd_percent"],
        )
        self.assertLess(measured["tone"]["end_to_end_thdn_percent"], 1.2)
        self.assertEqual(
            measured["calibration"]["status"],
            "field_calibrated_not_certified",
        )
        self.assertIsNone(measured["sharpness"]["din_45692_acum"])

    def test_loudness_reports_bs1770_and_true_peak(self):
        sample_rate = 48_000
        time = np.arange(sample_rate * 4, dtype=np.float64) / sample_rate
        audio = 0.1 * np.sin(2.0 * np.pi * 1000.0 * time)

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "mono.wav"
            sf.write(path, audio, sample_rate, subtype="PCM_24")
            results, _ = _analyze_with_context(path)

        self.assertIsInstance(results["loudness"]["integrated_lufs"], float)
        self.assertIsInstance(results["loudness"]["true_peak_dbtp"], float)
        self.assertIn("BS.1770-5", results["loudness"]["loudness_method"])
        self.assertLessEqual(results["distortion"]["hpss_analyzed_frame_count"], 2048)

    def test_visualizations_render_very_small_flatness_values(self):
        sample_rate = 48_000
        time = np.arange(sample_rate, dtype=np.float64) / sample_rate
        audio = 0.1 * np.sin(2.0 * np.pi * 1000.0 * time)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "tonal.wav"
            output = root / "plots"
            sf.write(path, audio, sample_rate, subtype="PCM_24")
            results, context = _analyze_with_context(path)
            saved = create_visualizations(context, results, output, "tonal_test")

            self.assertEqual(len(saved), 6)
            self.assertLess(results["flatness"]["mean"], 0.01)
            for saved_path in saved.values():
                self.assertGreater(Path(saved_path).stat().st_size, 0)

    def test_user_cancellation_does_not_append_failure_csv(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "results" / "cancelled"
            with (
                patch("audio_analyzer._analyze_with_context", side_effect=KeyboardInterrupt()),
                redirect_stdout(io.StringIO()),
                redirect_stderr(io.StringIO()),
            ):
                exit_code = main(
                    [
                        "cancelled.wav",
                        "--output-dir",
                        str(output),
                        "--no-save-plots",
                    ]
                )

            self.assertEqual(exit_code, 130)
            self.assertFalse((output.parent / "results.csv").exists())


if __name__ == "__main__":
    unittest.main()
