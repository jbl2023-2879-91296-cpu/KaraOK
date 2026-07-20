import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import MagicMock, patch

os.environ.setdefault("JWT_SECRET", "test-only-secret-that-is-at-least-32-characters")

import app as api


def _analyzer_result(status: str = "passed") -> dict:
    return {
        "analysis_information": {"analysis_status": "completed"},
        "bass": {"energy_percentage": 40.0},
        "treble": {"energy_percentage": 12.0},
        "loudness": {"integrated_lufs": -14.0},
        "flatness": {"mean": 0.03},
        "sharpness": {"normalized_score": 0.2},
        "noise": {"noise_dbfs": -42.0},
        "distortion": {"estimated_score": 8.0},
        "quality_assessment": {
            "status": status,
            "warnings": [],
            "failures": [],
        },
    }


class AudioPipelineTests(unittest.TestCase):
    def _run_with_fake_process(self, return_code: int, result_status: str = "passed"):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        audio_path = root / "input.wav"
        analyzer_path = root / "audio_analyzer.py"
        settings_path = root / "settings.json"
        audio_path.write_bytes(b"RIFF-test")
        analyzer_path.write_text("# test analyzer", encoding="utf-8")
        settings_path.write_text("{}", encoding="utf-8")

        def fake_run(command, **kwargs):
            output_dir = Path(command[command.index("--output-dir") + 1])
            output_dir.mkdir(parents=True, exist_ok=True)
            if return_code in api.ANALYZER_COMPLETED_EXIT_CODES:
                (output_dir / "test_analysis.json").write_text(
                    json.dumps(_analyzer_result(result_status)),
                    encoding="utf-8",
                )
            return subprocess.CompletedProcess(
                command,
                return_code,
                stdout="feature extraction complete",
                stderr="quality threshold warning" if return_code == 3 else "",
            )

        patches = (
            patch.object(api, "ANALYSIS_OUTPUT_DIR", str(root / "outputs")),
            patch.object(api, "AUDIO_ANALYZER_PATH", str(analyzer_path)),
            patch.object(api, "AUDIO_ANALYZER_SETTINGS_PATH", str(settings_path)),
            patch.object(api, "_execute_analyzer_command", side_effect=fake_run),
        )
        with patches[0], patches[1], patches[2], patches[3]:
            dump = api.run_audio_analyzer(
                str(audio_path),
                user_id=7,
                assessment_id=11,
                original_name="recording.wav",
                analysis_purpose="quality_evaluation",
            )
        return root, dump

    def test_analyzer_result_is_returned_and_working_files_are_removed(self):
        root, dump = self._run_with_fake_process(0)
        self.assertEqual(dump["analysis_status"], "completed")
        self.assertNotIn("placeholder_output", dump)
        self.assertEqual(dump["analysis"]["loudness"]["integrated_lufs"], -14.0)
        self.assertFalse((root / "outputs" / "7" / "11").exists())
        self.assertEqual(dump["upload"]["original_file_name"], "recording.wav")
        self.assertGreater(dump["empirical_quality"]["overall_score"], 0.0)
        self.assertEqual(
            set(dump["empirical_quality"]["features"]),
            {"loudness", "bass", "treble", "sharpness", "flatness"},
        )

    def test_quality_failure_exit_code_still_produces_completed_dump(self):
        _, dump = self._run_with_fake_process(3, result_status="failed")
        self.assertEqual(dump["analysis_status"], "completed")
        self.assertTrue(dump["analyzer_process"]["quality_thresholds_failed"])
        self.assertEqual(dump["analysis"]["quality_assessment"]["status"], "failed")

    def test_technical_analyzer_failure_returns_details_without_retaining_files(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        audio_path = root / "input.wav"
        analyzer_path = root / "audio_analyzer.py"
        settings_path = root / "settings.json"
        audio_path.write_bytes(b"RIFF-test")
        analyzer_path.write_text("# test analyzer", encoding="utf-8")
        settings_path.write_text("{}", encoding="utf-8")
        completed = subprocess.CompletedProcess(
            [],
            2,
            stdout="",
            stderr="invalid audio",
        )
        with patch.object(api, "ANALYSIS_OUTPUT_DIR", str(root / "outputs")), patch.object(
            api, "AUDIO_ANALYZER_PATH", str(analyzer_path)
        ), patch.object(
            api, "AUDIO_ANALYZER_SETTINGS_PATH", str(settings_path)
        ), patch.object(api, "_execute_analyzer_command", return_value=completed):
            with self.assertRaises(api.AudioAnalyzerExecutionError) as raised:
                api.run_audio_analyzer(
                    str(audio_path),
                    user_id=7,
                    assessment_id=12,
                    original_name="broken.wav",
                    analysis_purpose="quality_evaluation",
                )
        self.assertEqual(raised.exception.dump["analysis_status"], "failed")
        self.assertEqual(raised.exception.dump["analyzer_process"]["exit_code"], 2)
        self.assertFalse((root / "outputs" / "7" / "12").exists())

    def test_analyzer_timeout_writes_failed_dump(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        audio_path = root / "input.wav"
        analyzer_path = root / "audio_analyzer.py"
        settings_path = root / "settings.json"
        audio_path.write_bytes(b"RIFF-test")
        analyzer_path.write_text("# test analyzer", encoding="utf-8")
        settings_path.write_text("{}", encoding="utf-8")
        timeout = subprocess.TimeoutExpired([], 1, output="partial", stderr="slow")
        with patch.object(api, "ANALYSIS_OUTPUT_DIR", str(root / "outputs")), patch.object(
            api, "AUDIO_ANALYZER_PATH", str(analyzer_path)
        ), patch.object(
            api, "AUDIO_ANALYZER_SETTINGS_PATH", str(settings_path)
        ), patch.object(api, "AUDIO_ANALYSIS_TIMEOUT_SECONDS", 1), patch.object(
            api, "_execute_analyzer_command", side_effect=timeout
        ):
            with self.assertRaises(api.AudioAnalyzerExecutionError) as raised:
                api.run_audio_analyzer(
                    str(audio_path),
                    user_id=7,
                    assessment_id=14,
                    original_name="slow.wav",
                    analysis_purpose="settings_suggestion",
                )
        dump = raised.exception.dump
        self.assertEqual(dump["analysis_status"], "failed")
        self.assertIn("exceeded 1 seconds", dump["error"])
        self.assertEqual(dump["analyzer_process"]["stdout"], "partial")
        self.assertFalse((root / "outputs" / "7" / "14").exists())

    def test_persist_analysis_maps_extracted_features(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value
        cursor.fetchone.return_value = (4,)
        dump = {
            "analyzer_process": {"duration_seconds": 1.25},
            "analysis": _analyzer_result("warning"),
        }
        with patch.object(api, "get_db", return_value=connection):
            api.persist_audio_analysis(11, 13, dump)

        insert_result = next(
            call
            for call in cursor.execute.call_args_list
            if "INSERT INTO audio_analysis_result" in call.args[0]
        )
        values = insert_result.args[1]
        self.assertEqual(values[:3], (11, None, 4))
        self.assertAlmostEqual(values[3], 31.51069476184425)
        self.assertEqual(
            values[4:11],
            (-42.0, 8.0, 40.0, 12.0, -14.0, 0.2, 0.03),
        )
        self.assertEqual(values[11:14], ("bad", "bad", '["bass", "treble", "sharpness", "flatness"]'))
        self.assertIn('"overall_score": 31.51069476184425', values[14])
        self.assertEqual(values[15:], ("1.0.0", 30))
        statements = "\n".join(call.args[0] for call in cursor.execute.call_args_list)
        self.assertIn("assessment_status = 'Completed'", statements)
        self.assertIn("UPDATE audio_upload SET score", statements)
        connection.commit.assert_called_once()

    def test_legacy_null_score_is_computed_from_stored_features(self):
        row = {
            "score": None,
            "status": "Acceptable",
            "loudness": -11.2,
            "bass": 70.7,
            "treble": 0.13,
            "sharpness": 0.00075,
            "flatness": 0.000032,
        }

        enriched = api._enrich_audio_test_row(row)

        self.assertIsNotNone(enriched["score"])
        self.assertGreater(enriched["score"], 80.0)
        self.assertEqual(enriched["status"], "Acceptable")
        self.assertEqual(len(enriched["empirical_quality"]["features"]), 5)

    def test_analysis_without_matching_genre_does_not_invent_preset(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value
        cursor.fetchone.return_value = None
        dump = {
            "analyzer_process": {"duration_seconds": 1.25},
            "analysis": _analyzer_result("passed"),
        }

        with patch.object(api, "get_db", return_value=connection):
            api.persist_audio_analysis(21, 23, dump)

        insert_result = next(
            call
            for call in cursor.execute.call_args_list
            if "INSERT INTO audio_analysis_result" in call.args[0]
        )
        self.assertIsNone(insert_result.args[1][2])

    def test_historical_analysis_dump_is_rebuilt_from_database(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value
        cursor.fetchone.return_value = {
            "assessment_id": 11,
            "file_name": "recording.wav",
            "analysis_purpose": "quality_evaluation",
            "assessment_status": "Completed",
            "result_status": "Acceptable",
            "quality_score": 91.5,
            "noise_level": -42.0,
            "distortion_level": 8.0,
            "bass": 40.0,
            "treble": 12.0,
            "loudness": -14.0,
            "sharpness": 0.2,
            "flatness": 0.03,
            "empirical_status": "good",
            "worst_feature_status": "good",
            "worst_features": '["treble"]',
            "empirical_details": '{"overall_score": 91.5}',
            "scoring_algorithm_version": "1.0.0",
            "reference_recording_count": 30,
        }
        with api.app.test_request_context(
            "/api/audio-uploads/13/analysis-dump"
        ), patch.object(api, "get_db", return_value=connection):
            api.g.user_id = 7
            response = api.get_audio_analysis_dump.__wrapped__(13)

        payload = response.get_json()
        self.assertEqual(payload["analysis_status"], "completed")
        self.assertEqual(payload["analysis"]["bass"]["energy_percentage"], 40.0)
        self.assertEqual(payload["empirical_quality"]["overall_score"], 91.5)
        self.assertIn("JOIN assessment", cursor.execute.call_args.args[0])


if __name__ == "__main__":
    unittest.main()
