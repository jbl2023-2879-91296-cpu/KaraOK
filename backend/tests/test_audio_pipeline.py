import json
from datetime import datetime, timedelta, timezone
from io import BytesIO
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import MagicMock, PropertyMock, patch

os.environ.setdefault("JWT_SECRET", "test-only-secret-that-is-at-least-32-characters")

import app as api
from audio_thresholds import load_genre_profiles, load_thresholds
from karaok.modules.settings_recommendations import service as recommendation_service
from settings_recommendations import ALGORITHM_VERSION, AmplifierScale, KnobSettings


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


def _stored_settings_columns() -> dict:
    current = {
        "volume": 5.0,
        "bass": 4.0,
        "treble": 6.0,
        "sharpness": 5.0,
        "flatness": 5.0,
    }
    recommended = {
        "volume": 5.5,
        "bass": 5.5,
        "treble": 5.5,
        "sharpness": 5.0,
        "flatness": 4.5,
    }
    adjustments = {
        name: {
            "current": current[name],
            "recommended": recommended[name],
            "delta": recommended[name] - current[name],
            "delta_normalized": 0.0,
            "reason_code": "within_genre_range",
            "confidence": "medium",
        }
        for name in current
    }
    return {
        "settings_recommendation_id": 41,
        "settings_assessment_id": 11,
        "settings_amplifier_profile_id": 12,
        "settings_parent_recommendation_id": None,
        "settings_genre": "rock",
        "settings_current_positions": json.dumps(current),
        "settings_recommended_positions": json.dumps(recommended),
        "settings_adjustments": json.dumps(adjustments),
        "settings_original_score": 72.0,
        "settings_verification_score": None,
        "settings_overall_confidence": "medium",
        "settings_algorithm_version": "1.0.0",
        "settings_genre_profile_version": "2026.09.1",
        "settings_genre_profile_checksum": load_genre_profiles().artifact_checksum,
        "settings_recommendation_status": "generated",
        "settings_created_at": datetime(2026, 9, 2, tzinfo=timezone.utc),
        "settings_applied_at": None,
        "settings_scale_min": 0.0,
        "settings_scale_max": 10.0,
        "settings_scale_step": 0.5,
    }


class AudioPipelineTests(unittest.TestCase):
    def _post_guest_audio(
        self,
        *,
        analysis_purpose: str,
        genre: str = "rock",
        current_settings: dict | None = None,
        verification_token: str | None = None,
        feature_enabled: bool = True,
    ):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        upload_root = root / "uploads"
        analysis_root = root / "analysis"
        dump = {
            "analysis_status": "completed",
            "analysis_purpose": analysis_purpose,
            "upload": {
                "assessment_id": 99,
                "original_file_name": "guest.wav",
            },
            "analyzer_process": {"duration_seconds": 0.5},
            "analysis": _analyzer_result("passed"),
            "visualizations": {
                "waveform": "0/99/guest_waveform.png",
                "spectrogram": "0/99/guest_spectrogram.png",
            },
        }
        report_directory = analysis_root / "0" / "99"
        report_directory.mkdir(parents=True)
        png = b"\x89PNG\r\n\x1a\nserver-generated-report"
        (report_directory / "guest_waveform.png").write_bytes(png)
        (report_directory / "guest_spectrogram.png").write_bytes(png)
        data = {
            "audio": (BytesIO(b"RIFF-test"), "guest.wav"),
            "duration_seconds": "2",
            "analysis_purpose": analysis_purpose,
        }
        if analysis_purpose == "settings_suggestion":
            data.update(
                {
                    "genre": genre,
                    "amplifier_scale": json.dumps(
                        {"minimum": 0, "maximum": 10, "step": 0.5}
                    ),
                    "current_settings": json.dumps(
                        current_settings
                        or {
                            "volume": 5,
                            "bass": 4,
                            "treble": 6,
                            "sharpness": 5,
                            "flatness": 5,
                        }
                    ),
                }
            )
            if verification_token is not None:
                data["verification_token"] = verification_token

        with api.app.test_request_context(
            "/api/guest/audio-analysis",
            method="POST",
            data=data,
            content_type="multipart/form-data",
        ), patch.object(
            api, "SETTINGS_RECOMMENDATIONS_ENABLED", feature_enabled
        ), patch.object(
            api, "AUDIO_UPLOAD_DIR", str(upload_root)
        ), patch.object(
            api, "ANALYSIS_OUTPUT_DIR", str(analysis_root)
        ), patch.object(
            api, "audio_duration_seconds", return_value=2
        ), patch.object(
            api, "run_audio_analyzer", return_value=dump
        ), patch.object(
            api, "get_db", side_effect=AssertionError("guest history must not persist")
        ):
            result = api.create_guest_audio_analysis.__wrapped__()
        return result, upload_root

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
                (output_dir / "test_waveform.png").write_bytes(b"waveform")
                (output_dir / "test_spectrogram.png").write_bytes(b"spectrogram")
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

    def test_analyzer_result_retains_only_real_report_visualizations(self):
        root, dump = self._run_with_fake_process(0)
        self.assertEqual(dump["analysis_status"], "completed")
        self.assertNotIn("placeholder_output", dump)
        self.assertEqual(dump["analysis"]["loudness"]["integrated_lufs"], -14.0)
        output = root / "outputs" / "7" / "11"
        self.assertTrue(output.is_dir())
        self.assertEqual(
            {path.name for path in output.iterdir()},
            {"test_waveform.png", "test_spectrogram.png"},
        )
        self.assertEqual(
            dump["visualizations"],
            {
                "waveform": "7/11/test_waveform.png",
                "spectrogram": "7/11/test_spectrogram.png",
            },
        )
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
            "visualizations": {
                "waveform": "7/11/test_waveform.png",
                "spectrogram": "7/11/test_spectrogram.png",
            },
        }
        with patch.object(api, "get_db", return_value=connection):
            api.persist_audio_analysis(11, 13, dump)

        insert_result = next(
            call
            for call in cursor.execute.call_args_list
            if "INSERT INTO audio_analysis_result" in call.args[0]
        )
        thresholds = load_thresholds()
        statement = insert_result.args[0]
        values = insert_result.args[1]
        self.assertIn("quality_profile_version", statement)
        self.assertIn("quality_profile_checksum", statement)
        self.assertEqual(values[0], 11)
        self.assertAlmostEqual(values[1], 31.51069476184425)
        self.assertEqual(
            values[2:9],
            (-42.0, 8.0, 40.0, 12.0, -14.0, 0.2, 0.03),
        )
        self.assertEqual(values[9:12], ("bad", "bad", '["bass", "treble", "sharpness", "flatness"]'))
        self.assertIn('"overall_score": 31.51069476184425', values[12])
        self.assertEqual(
            values[13:],
            (
                "1.0.0",
                thresholds["quality_profile_version"],
                thresholds["artifact_checksum"],
                30,
                "7/11/test_waveform.png",
                "7/11/test_spectrogram.png",
            ),
        )
        statements = "\n".join(call.args[0] for call in cursor.execute.call_args_list)
        self.assertIn("assessment_status = 'Completed'", statements)
        self.assertIn("UPDATE audio_upload SET score", statements)
        connection.commit.assert_called_once()

    def test_manual_audio_test_persists_validated_quality_provenance(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value
        cursor.lastrowid = 51
        thresholds = load_thresholds()

        with api.app.test_request_context(
            "/api/audio-tests",
            method="POST",
            json={
                "test_name": "Manual instrumental result",
                "score": 88,
                "noise_level": -42,
                "distortion_level": 4,
            },
        ), patch.object(api, "get_db", return_value=connection), patch.object(
            api, "audit"
        ):
            api.g.user_id = 7
            _, status_code = api.create_audio_test.__wrapped__()

        self.assertEqual(status_code, 201)
        insert_result = next(
            call
            for call in cursor.execute.call_args_list
            if "INSERT INTO audio_analysis_result" in call.args[0]
        )
        self.assertNotIn("threshold_id", insert_result.args[0])
        self.assertNotIn("preset_id", insert_result.args[0])
        self.assertEqual(
            insert_result.args[1],
            (
                51,
                88,
                -42.0,
                4.0,
                thresholds["algorithm_version"],
                thresholds["quality_profile_version"],
                thresholds["artifact_checksum"],
            ),
        )
        connection.commit.assert_called_once()

    def test_analysis_and_recommendation_share_one_commit(self):
        summary_dump = {
            "analyzer_process": {"duration_seconds": 1.25},
            "analysis": _analyzer_result("passed"),
            "visualizations": {
                "waveform": "7/11/test_waveform.png",
                "spectrogram": "7/11/test_spectrogram.png",
            },
        }
        context = recommendation_service.SuggestionContext(
            guest=False,
            user_id=7,
            genre="rock",
            scale=AmplifierScale(0, 10, 0.5),
            current=KnobSettings(5, 4, 6, 5, 5),
            amplifier_profile_id=12,
        )
        summary = api.summarize_audio_analysis(summary_dump)
        recommendation = recommendation_service.build_recommendation(
            summary,
            context,
            verification=False,
        )
        connection = MagicMock()
        cursor = connection.cursor.return_value
        cursor.lastrowid = 41

        with patch.object(api, "get_db", return_value=connection):
            result = api.persist_audio_analysis(
                11,
                13,
                summary_dump,
                recommendation=recommendation,
                recommendation_context=context,
            )

        statements = [call.args[0] for call in cursor.execute.call_args_list]
        analysis_index = next(
            index
            for index, statement in enumerate(statements)
            if "INSERT INTO audio_analysis_result" in statement
        )
        recommendation_index = next(
            index
            for index, statement in enumerate(statements)
            if "INSERT INTO settings_recommendation" in statement
        )
        assessment_index = next(
            index
            for index, statement in enumerate(statements)
            if "UPDATE assessment" in statement
        )
        self.assertLess(analysis_index, recommendation_index)
        self.assertLess(recommendation_index, assessment_index)
        self.assertFalse(any("genre_preset" in statement for statement in statements))
        recommendation_insert = cursor.execute.call_args_list[recommendation_index]
        self.assertIn("genre_profile_checksum", recommendation_insert.args[0])
        self.assertEqual(
            recommendation_insert.args[1][13],
            recommendation.profile_checksum,
        )
        self.assertEqual(result["settings_recommendation"]["id"], 41)
        connection.commit.assert_called_once()

    def test_summary_maps_analyzer_clipping_noise_and_distortion_safety(self):
        analysis = _analyzer_result("failed")
        analysis["distortion"].update(
            {
                "clipped_sample_percentage": 0.75,
                "estimated_score": 55.0,
            }
        )
        analysis["quality_assessment"].update(
            {
                "measured": {"estimated_snr_db": 8.0},
                "thresholds": {
                    "clipped_samples_failure_above_percentage": 0.5,
                    "distortion_warning_above": 40.0,
                    "snr_warning_below_db": 12.0,
                },
            }
        )

        summary = api.summarize_audio_analysis({"analysis": analysis})

        self.assertTrue(summary["safety_signals"]["clipping"])
        self.assertTrue(summary["safety_signals"]["excessive_noise"])
        self.assertTrue(summary["safety_signals"]["excessive_distortion"])

    def test_authenticated_settings_upload_uses_two_transaction_commits(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        context = recommendation_service.SuggestionContext(
            guest=False,
            user_id=7,
            genre="rock",
            scale=AmplifierScale(0, 10, 0.5),
            current=KnobSettings(5, 4, 6, 5, 5),
            amplifier_profile_id=12,
        )
        dump = {
            "analysis_status": "completed",
            "analysis_purpose": "settings_suggestion",
            "upload": {
                "assessment_id": 11,
                "original_file_name": "recording.wav",
            },
            "analyzer_process": {"duration_seconds": 0.5},
            "analysis": _analyzer_result("passed"),
            "visualizations": {
                "waveform": "7/11/recording_waveform.png",
                "spectrogram": "7/11/recording_spectrogram.png",
            },
        }
        pending_connection = MagicMock()
        pending_cursor = pending_connection.cursor.return_value
        type(pending_cursor).lastrowid = PropertyMock(side_effect=[11, 13])
        result_connection = MagicMock()
        result_cursor = result_connection.cursor.return_value
        result_cursor.lastrowid = 41

        with api.app.test_request_context(
            "/api/audio-uploads",
            method="POST",
            data={
                "audio": (BytesIO(b"RIFF-test"), "recording.wav"),
                "duration_seconds": "2",
                "analysis_purpose": "settings_suggestion",
                "genre": "rock",
                "amplifier_profile_id": "12",
                "current_settings": json.dumps(context.current.to_dict()),
            },
            content_type="multipart/form-data",
        ), patch.object(
            api, "AUDIO_UPLOAD_DIR", str(root / "uploads")
        ), patch.object(
            api, "SETTINGS_RECOMMENDATIONS_ENABLED", True
        ), patch.object(
            api.settings_recommendation_service,
            "parse_suggestion_form",
            return_value=context,
        ), patch.object(
            api, "audio_duration_seconds", return_value=2
        ), patch.object(
            api, "run_audio_analyzer", return_value=dump
        ), patch.object(
            api,
            "get_db",
            side_effect=[pending_connection, result_connection],
        ), patch.object(api, "audit"):
            api.g.user_id = 7
            response, status_code = api.create_audio_upload.__wrapped__()

        payload = response.get_json()
        self.assertEqual(status_code, 201)
        self.assertEqual(payload["settings_recommendation"]["id"], 41)
        self.assertTrue(payload["settings_recommendation"]["persisted"])
        pending_connection.commit.assert_called_once()
        result_connection.commit.assert_called_once()

    def test_recommendation_insert_failure_rolls_back_analysis_transaction(self):
        context = recommendation_service.SuggestionContext(
            guest=False,
            user_id=7,
            genre="rock",
            scale=AmplifierScale(0, 10, 0.5),
            current=KnobSettings(5, 4, 6, 5, 5),
            amplifier_profile_id=12,
        )
        dump = {
            "analyzer_process": {"duration_seconds": 1.25},
            "analysis": _analyzer_result("passed"),
            "visualizations": {
                "waveform": "7/11/test_waveform.png",
                "spectrogram": "7/11/test_spectrogram.png",
            },
        }
        recommendation = recommendation_service.build_recommendation(
            api.summarize_audio_analysis(dump),
            context,
            verification=False,
        )
        connection = MagicMock()
        cursor = connection.cursor.return_value

        def execute(statement, parameters=None):
            if "INSERT INTO settings_recommendation" in statement:
                raise RuntimeError("database unavailable")

        cursor.execute.side_effect = execute
        with patch.object(api, "get_db", return_value=connection):
            with self.assertRaisesRegex(RuntimeError, "database unavailable"):
                api.persist_audio_analysis(
                    11,
                    13,
                    dump,
                    recommendation=recommendation,
                    recommendation_context=context,
                )

        connection.commit.assert_not_called()
        connection.rollback.assert_called_once()

    def test_authenticated_verification_persists_score_comparison_and_rollback(self):
        context = recommendation_service.SuggestionContext(
            guest=False,
            user_id=7,
            genre="rock",
            scale=AmplifierScale(0, 10, 0.5),
            current=KnobSettings(5.5, 5.5, 5.5, 5, 4.5),
            amplifier_profile_id=12,
            verification_of=41,
            before_score=80.0,
        )
        dump = {
            "analyzer_process": {"duration_seconds": 1.25},
            "analysis": _analyzer_result("passed"),
            "visualizations": {
                "waveform": "7/11/test_waveform.png",
                "spectrogram": "7/11/test_spectrogram.png",
            },
        }
        recommendation = recommendation_service.build_recommendation(
            api.summarize_audio_analysis(dump),
            context,
            verification=True,
        )
        connection = MagicMock()
        cursor = connection.cursor.return_value
        cursor.fetchone.return_value = {
            "recommendation_id": 41,
            "genre_profile_version": recommendation.profile_version,
            "genre_profile_checksum": recommendation.profile_checksum,
        }
        cursor.lastrowid = 42
        cursor.rowcount = 1

        with patch.object(api, "get_db", return_value=connection):
            result = api.persist_audio_analysis(
                11,
                13,
                dump,
                recommendation=recommendation,
                recommendation_context=context,
            )

        payload = result["settings_recommendation"]
        self.assertEqual(payload["before_score"], 80.0)
        self.assertLess(payload["after_score"], payload["before_score"])
        self.assertEqual(payload["verification_status"], "worsened")
        self.assertTrue(payload["rollback_recommended"])
        parent_select = next(
            call
            for call in cursor.execute.call_args_list
            if "FOR UPDATE" in call.args[0]
            and "FROM settings_recommendation" in call.args[0]
        )
        self.assertIn("sr.genre_profile_version = %s", parent_select.args[0])
        self.assertIn("sr.genre_profile_checksum = %s", parent_select.args[0])
        self.assertEqual(
            parent_select.args[1],
            (
                41,
                7,
                12,
                recommendation.profile_version,
                recommendation.profile_checksum,
            ),
        )
        parent_update = next(
            call
            for call in cursor.execute.call_args_list
            if "UPDATE settings_recommendation" in call.args[0]
        )
        self.assertEqual(
            parent_update.args[1],
            (payload["after_score"], "reverted", 41, 7),
        )
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
        self.assertEqual(
            enriched["quality_profile_version"],
            enriched["empirical_quality"]["quality_profile_version"],
        )
        self.assertEqual(
            enriched["quality_profile_checksum"],
            enriched["empirical_quality"]["quality_profile_checksum"],
        )

    def test_stored_score_and_provenance_with_null_empirical_fields_is_not_rescored(self):
        row = {
            "score": 72.0,
            "status": "Needs Improvement",
            "loudness": -99.0,
            "bass": 99.0,
            "treble": 99.0,
            "sharpness": 99.0,
            "flatness": 0.99,
            "empirical_status": None,
            "worst_feature_status": None,
            "worst_features": None,
            "empirical_details": None,
            "scoring_algorithm_version": "historical-algorithm",
            "quality_profile_version": "historical-quality-v1",
            "quality_profile_checksum": "b" * 64,
            "reference_recording_count": 30,
        }

        with patch.object(api, "evaluate_features") as evaluate:
            enriched = api._enrich_audio_test_row(row)

        evaluate.assert_not_called()
        self.assertEqual(enriched["score"], 72.0)
        self.assertEqual(enriched["status"], "Needs Improvement")
        self.assertEqual(enriched["empirical_quality"]["overall_score"], 72.0)
        self.assertEqual(
            enriched["empirical_quality"]["overall_status"],
            "good_but_needs_improvement",
        )
        self.assertEqual(enriched["empirical_quality"]["worst_features"], [])
        self.assertEqual(
            enriched["empirical_quality"]["quality_profile_version"],
            "historical-quality-v1",
        )
        self.assertEqual(
            enriched["empirical_quality"]["quality_profile_checksum"],
            "b" * 64,
        )

    def test_detail_only_status_and_provenance_normalize_public_snapshot(self):
        row = {
            "score": 72.0,
            "status": "Needs Improvement",
            "empirical_status": None,
            "worst_feature_status": None,
            "worst_features": None,
            "empirical_details": json.dumps(
                {
                    "overall_status": "good",
                    "algorithm_version": "detail-algorithm",
                    "quality_profile_version": "detail-quality-v1",
                    "quality_profile_checksum": "a" * 64,
                    "reference_recording_count": 31,
                }
            ),
            "scoring_algorithm_version": None,
            "quality_profile_version": None,
            "quality_profile_checksum": None,
            "reference_recording_count": None,
        }

        enriched = api._enrich_audio_test_row(row)

        self.assertEqual(enriched["status"], "Acceptable")
        self.assertEqual(enriched["empirical_status"], "good")
        self.assertEqual(enriched["empirical_quality"]["overall_status"], "good")
        self.assertEqual(enriched["scoring_algorithm_version"], "detail-algorithm")
        self.assertEqual(enriched["quality_profile_version"], "detail-quality-v1")
        self.assertEqual(enriched["quality_profile_checksum"], "a" * 64)
        self.assertEqual(enriched["reference_recording_count"], 31)
        self.assertEqual(
            enriched["empirical_quality"]["algorithm_version"],
            "detail-algorithm",
        )
        self.assertEqual(
            enriched["empirical_quality"]["quality_profile_version"],
            "detail-quality-v1",
        )
        self.assertEqual(
            enriched["empirical_quality"]["quality_profile_checksum"],
            "a" * 64,
        )
        self.assertEqual(
            enriched["empirical_quality"]["reference_recording_count"], 31
        )

    def test_invalid_detail_only_provenance_is_not_promoted(self):
        row = {
            "score": 72.0,
            "status": "Needs Improvement",
            "empirical_status": None,
            "worst_feature_status": None,
            "worst_features": None,
            "empirical_details": json.dumps(
                {
                    "overall_status": "future_status",
                    "algorithm_version": 99,
                    "quality_profile_version": "",
                    "quality_profile_checksum": "not-a-checksum",
                    "reference_recording_count": "31",
                }
            ),
            "scoring_algorithm_version": None,
            "quality_profile_version": None,
            "quality_profile_checksum": None,
            "reference_recording_count": None,
        }

        enriched = api._enrich_audio_test_row(row)

        self.assertEqual(enriched["status"], "Needs Improvement")
        self.assertEqual(
            enriched["empirical_status"], "good_but_needs_improvement"
        )
        for row_field, empirical_field in (
            ("scoring_algorithm_version", "algorithm_version"),
            ("quality_profile_version", "quality_profile_version"),
            ("quality_profile_checksum", "quality_profile_checksum"),
            ("reference_recording_count", "reference_recording_count"),
        ):
            self.assertIsNone(enriched[row_field])
            self.assertNotIn(empirical_field, enriched["empirical_quality"])

    def test_null_score_with_stored_provenance_is_not_legacy_backfill(self):
        row = {
            "score": None,
            "status": "Acceptable",
            "loudness": -11.2,
            "bass": 70.7,
            "treble": 0.13,
            "sharpness": 0.00075,
            "flatness": 0.000032,
            "empirical_status": None,
            "worst_feature_status": None,
            "worst_features": None,
            "empirical_details": None,
            "scoring_algorithm_version": "historical-algorithm",
            "quality_profile_version": "historical-quality-v1",
            "quality_profile_checksum": "b" * 64,
            "reference_recording_count": 30,
        }

        with patch.object(api, "evaluate_features") as evaluate:
            enriched = api._enrich_audio_test_row(row)

        evaluate.assert_not_called()
        self.assertIsNone(enriched["score"])
        self.assertNotIn("overall_score", enriched["empirical_quality"])
        self.assertEqual(enriched["status"], "Acceptable")
        self.assertEqual(
            enriched["empirical_quality"]["quality_profile_version"],
            "historical-quality-v1",
        )

    def test_stored_empirical_columns_override_conflicting_detail_json(self):
        row = {
            "score": 91.5,
            "status": "Problematic",
            "empirical_status": "good",
            "worst_feature_status": "good_but_needs_improvement",
            "worst_features": '["treble"]',
            "empirical_details": json.dumps(
                {
                    "overall_score": 1.0,
                    "overall_status": "bad",
                    "worst_feature_status": "bad",
                    "worst_features": ["bass"],
                    "algorithm_version": "conflicting-algorithm",
                    "quality_profile_version": "conflicting-quality",
                    "quality_profile_checksum": "c" * 64,
                    "reference_recording_count": 999,
                    "features": {"bass": {"status": "bad"}},
                }
            ),
            "scoring_algorithm_version": "historical-algorithm",
            "quality_profile_version": "historical-quality-v1",
            "quality_profile_checksum": "b" * 64,
            "reference_recording_count": 30,
        }

        enriched = api._enrich_audio_test_row(row)

        empirical = enriched["empirical_quality"]
        self.assertEqual(enriched["status"], "Acceptable")
        self.assertEqual(enriched["empirical_status"], "good")
        self.assertEqual(enriched["scoring_algorithm_version"], "historical-algorithm")
        self.assertEqual(enriched["quality_profile_version"], "historical-quality-v1")
        self.assertEqual(enriched["quality_profile_checksum"], "b" * 64)
        self.assertEqual(enriched["reference_recording_count"], 30)
        self.assertEqual(empirical["overall_score"], 91.5)
        self.assertEqual(empirical["overall_status"], "good")
        self.assertEqual(
            empirical["worst_feature_status"], "good_but_needs_improvement"
        )
        self.assertEqual(empirical["worst_features"], ["treble"])
        self.assertEqual(empirical["algorithm_version"], "historical-algorithm")
        self.assertEqual(empirical["quality_profile_version"], "historical-quality-v1")
        self.assertEqual(empirical["quality_profile_checksum"], "b" * 64)
        self.assertEqual(empirical["reference_recording_count"], 30)
        self.assertEqual(empirical["features"]["bass"]["status"], "bad")

    def test_malformed_empirical_details_is_not_exposed_as_non_object(self):
        for raw_details in ("not-json", '["not", "an", "object"]', ["list"]):
            with self.subTest(raw_details=raw_details):
                row = {
                    "score": 88.0,
                    "status": "Acceptable",
                    "empirical_status": "good",
                    "worst_feature_status": "good",
                    "worst_features": '["bass"]',
                    "empirical_details": raw_details,
                }

                enriched = api._enrich_audio_test_row(row)

                self.assertIsInstance(enriched["empirical_quality"], dict)
                self.assertEqual(enriched["empirical_quality"]["overall_score"], 88.0)
                self.assertEqual(enriched["empirical_quality"]["worst_features"], ["bass"])

    def test_malformed_worst_features_column_preserves_typed_detail_data(self):
        for raw_worst_features in (None, "not-json", '["bass", 3]'):
            with self.subTest(raw_worst_features=raw_worst_features):
                row = {
                    "score": 91.5,
                    "status": "Acceptable",
                    "empirical_status": "good",
                    "worst_feature_status": "good",
                    "worst_features": raw_worst_features,
                    "empirical_details": json.dumps(
                        {
                            "overall_score": 91.5,
                            "overall_status": "good",
                            "worst_features": ["flatness"],
                        }
                    ),
                }

                enriched = api._enrich_audio_test_row(row)

                self.assertEqual(
                    enriched["empirical_quality"]["worst_features"],
                    ["flatness"],
                )

    def test_unsupported_stored_empirical_status_falls_back_and_logs_corruption(self):
        row = {
            "score": 91.5,
            "status": "Problematic",
            "empirical_status": "future_status",
            "worst_feature_status": "bad",
            "worst_features": "[]",
            "empirical_details": '{"overall_status": "good"}',
        }

        with patch.object(api.app.logger, "warning") as warning:
            enriched = api._enrich_audio_test_row(row)

        self.assertEqual(enriched["status"], "Problematic")
        self.assertEqual(enriched["empirical_quality"]["overall_status"], "bad")
        warning.assert_called_once()

    def test_historical_assessment_helper_uses_persisted_empirical_result(self):
        row = {
            "score": 91.5,
            "status": "Problematic",
            "loudness": -99.0,
            "bass": 99.0,
            "treble": 99.0,
            "sharpness": 99.0,
            "flatness": 0.99,
            "empirical_status": "good",
            "worst_feature_status": "good_but_needs_improvement",
            "worst_features": '["treble"]',
            "empirical_details": json.dumps(
                {
                    "overall_score": 91.5,
                    "overall_status": "good",
                    "worst_feature_status": "good_but_needs_improvement",
                    "worst_features": ["treble"],
                    "reference": {"source_sha256": "stored-source"},
                }
            ),
            "quality_profile_version": "historical-quality-v1",
            "quality_profile_checksum": "b" * 64,
        }
        current_result = {
            "overall_score": 2.0,
            "overall_status": "bad",
            "worst_feature_status": "bad",
            "worst_features": ["loudness", "bass"],
            "features": {},
        }

        with patch.object(api, "evaluate_features", return_value=current_result) as evaluate:
            enriched = api._enrich_audio_test_row(row)

        evaluate.assert_not_called()
        self.assertEqual(enriched["score"], 91.5)
        self.assertEqual(enriched["status"], "Acceptable")
        self.assertEqual(enriched["empirical_quality"]["overall_score"], 91.5)
        self.assertEqual(enriched["empirical_quality"]["overall_status"], "good")
        self.assertEqual(
            enriched["empirical_quality"]["worst_feature_status"],
            "good_but_needs_improvement",
        )
        self.assertEqual(enriched["empirical_quality"]["worst_features"], ["treble"])
        self.assertEqual(
            enriched["empirical_quality"]["reference"]["source_sha256"],
            "stored-source",
        )
        self.assertEqual(enriched["quality_profile_version"], "historical-quality-v1")
        self.assertEqual(enriched["quality_profile_checksum"], "b" * 64)

    def test_assessment_list_and_detail_select_persisted_empirical_fields(self):
        for route in ("list", "detail"):
            with self.subTest(route=route):
                connection = MagicMock()
                cursor = connection.cursor.return_value
                row = {
                    "id": 11,
                    "test_name": "recording.wav",
                    "score": 91.5,
                    "noise_level": -42.0,
                    "distortion_level": 8.0,
                    "bass": 40.0,
                    "treble": 12.0,
                    "loudness": -14.0,
                    "sharpness": 0.2,
                    "flatness": 0.03,
                    "empirical_status": "good",
                    "worst_feature_status": "good",
                    "worst_features": "[]",
                    "empirical_details": '{"overall_score": 91.5}',
                    "quality_profile_version": "historical-quality-v1",
                    "quality_profile_checksum": "b" * 64,
                    "status": "Acceptable",
                    "assessment_status": "Completed",
                    "analysis_purpose": "quality_evaluation",
                    "duration_seconds": 2,
                    "created_at": datetime(2026, 9, 2, tzinfo=timezone.utc),
                }
                if route == "list":
                    cursor.fetchall.return_value = [row]
                    request_path = "/api/audio-tests"
                else:
                    cursor.fetchone.return_value = row
                    request_path = "/api/audio-tests/11"

                with api.app.test_request_context(request_path), patch.object(
                    api, "get_db", return_value=connection
                ):
                    api.g.user_id = 7
                    if route == "list":
                        response = api.get_audio_tests.__wrapped__()
                    else:
                        response, status_code = api.get_audio_test.__wrapped__(11)
                        self.assertEqual(status_code, 200)

                payload = response.get_json()
                payload = payload[0] if route == "list" else payload
                self.assertEqual(payload["empirical_quality"]["overall_score"], 91.5)
                for raw_field in (
                    "empirical_status",
                    "worst_feature_status",
                    "worst_features",
                    "empirical_details",
                ):
                    self.assertNotIn(raw_field, payload)
                statement = cursor.execute.call_args.args[0]
                for column in (
                    "r.empirical_status",
                    "r.worst_feature_status",
                    "r.worst_features",
                    "r.empirical_details",
                    "r.scoring_algorithm_version",
                    "r.reference_recording_count",
                ):
                    self.assertIn(column, statement)

    def test_analysis_persistence_has_no_genre_lookup(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value
        dump = {
            "analyzer_process": {"duration_seconds": 1.25},
            "analysis": _analyzer_result("passed"),
            "visualizations": {
                "waveform": "7/21/test_waveform.png",
                "spectrogram": "7/21/test_spectrogram.png",
            },
        }

        with patch.object(api, "get_db", return_value=connection):
            api.persist_audio_analysis(21, 23, dump)

        insert_result = next(
            call
            for call in cursor.execute.call_args_list
            if "INSERT INTO audio_analysis_result" in call.args[0]
        )
        statements = [call.args[0] for call in cursor.execute.call_args_list]
        self.assertFalse(any("genre_preset" in statement for statement in statements))
        self.assertNotIn("preset_id", insert_result.args[0])

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
            "quality_profile_version": "2026.09.1",
            "quality_profile_checksum": "b" * 64,
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
        self.assertEqual(payload["quality_profile_version"], "2026.09.1")
        self.assertEqual(payload["quality_profile_checksum"], "b" * 64)
        statement = cursor.execute.call_args.args[0]
        self.assertIn("r.quality_profile_version", statement)
        self.assertIn("r.quality_profile_checksum", statement)
        self.assertIn("JOIN assessment", cursor.execute.call_args.args[0])

    def test_historical_analysis_dump_uses_normalized_detail_only_snapshot(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value
        cursor.fetchone.return_value = {
            "assessment_id": 11,
            "file_name": "recording.wav",
            "analysis_purpose": "quality_evaluation",
            "assessment_status": "Completed",
            "result_status": "Needs Improvement",
            "quality_score": 72.0,
            "noise_level": -42.0,
            "distortion_level": 8.0,
            "bass": 40.0,
            "treble": 12.0,
            "loudness": -14.0,
            "sharpness": 0.2,
            "flatness": 0.03,
            "empirical_status": None,
            "worst_feature_status": None,
            "worst_features": None,
            "empirical_details": json.dumps(
                {
                    "overall_status": "good",
                    "algorithm_version": "detail-algorithm",
                    "quality_profile_version": "detail-quality-v1",
                    "quality_profile_checksum": "a" * 64,
                    "reference_recording_count": 31,
                }
            ),
            "scoring_algorithm_version": None,
            "quality_profile_version": None,
            "quality_profile_checksum": None,
            "reference_recording_count": None,
        }

        with api.app.test_request_context(
            "/api/audio-uploads/13/analysis-dump"
        ), patch.object(api, "get_db", return_value=connection):
            api.g.user_id = 7
            response = api.get_audio_analysis_dump.__wrapped__(13)

        payload = response.get_json()
        quality = payload["analysis"]["quality_assessment"]
        self.assertEqual(quality["status"], "Acceptable")
        self.assertEqual(quality["empirical_status"], "good")
        self.assertEqual(payload["scoring_algorithm_version"], "detail-algorithm")
        self.assertEqual(payload["quality_profile_version"], "detail-quality-v1")
        self.assertEqual(payload["quality_profile_checksum"], "a" * 64)
        self.assertEqual(payload["reference_recording_count"], 31)

    def test_historical_analysis_dump_normalizes_conflicting_and_malformed_fields(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value
        cursor.fetchone.return_value = {
            "assessment_id": 11,
            "file_name": "recording.wav",
            "analysis_purpose": "quality_evaluation",
            "assessment_status": "Completed",
            "result_status": "Needs Improvement",
            "quality_score": 72.0,
            "noise_level": -42.0,
            "distortion_level": 8.0,
            "bass": 40.0,
            "treble": 12.0,
            "loudness": -14.0,
            "sharpness": 0.2,
            "flatness": 0.03,
            "empirical_status": "future_status",
            "worst_feature_status": "good_but_needs_improvement",
            "worst_features": '["treble", 3]',
            "empirical_details": json.dumps(
                {
                    "overall_score": 1.0,
                    "overall_status": "bad",
                    "worst_feature_status": "bad",
                    "worst_features": ["flatness"],
                }
            ),
            "scoring_algorithm_version": "historical-algorithm",
            "quality_profile_version": "historical-quality-v1",
            "quality_profile_checksum": "b" * 64,
            "reference_recording_count": 30,
        }
        with api.app.test_request_context(
            "/api/audio-uploads/13/analysis-dump"
        ), patch.object(api, "get_db", return_value=connection), patch.object(
            api.app.logger, "warning"
        ) as warning:
            api.g.user_id = 7
            response = api.get_audio_analysis_dump.__wrapped__(13)

        payload = response.get_json()
        quality = payload["analysis"]["quality_assessment"]
        self.assertEqual(quality["status"], "Needs Improvement")
        self.assertEqual(quality["empirical_status"], "good_but_needs_improvement")
        self.assertEqual(quality["worst_feature_status"], "good_but_needs_improvement")
        self.assertEqual(quality["worst_features"], ["flatness"])
        self.assertEqual(payload["empirical_quality"]["overall_score"], 72.0)
        self.assertEqual(
            payload["empirical_quality"]["quality_profile_version"],
            "historical-quality-v1",
        )
        warning.assert_called_once()

    def test_settings_assessment_detail_rebuilds_persisted_recommendation(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value
        cursor.fetchone.return_value = {
            "id": 11,
            "test_name": "recording.wav",
            "score": 72.0,
            "noise_level": -42.0,
            "distortion_level": 8.0,
            "bass": 40.0,
            "treble": 12.0,
            "loudness": -14.0,
            "sharpness": 0.2,
            "flatness": 0.03,
            "status": "Problematic",
            "assessment_status": "Completed",
            "analysis_purpose": "settings_suggestion",
            "duration_seconds": 2,
            "created_at": datetime(2026, 9, 2, tzinfo=timezone.utc),
            "quality_profile_version": "2026.09.1",
            "quality_profile_checksum": "b" * 64,
            **_stored_settings_columns(),
        }

        with api.app.test_request_context("/api/audio-tests/11"), patch.object(
            api, "get_db", return_value=connection
        ), patch.object(api, "evaluate_features") as evaluate:
            api.g.user_id = 7
            response, status_code = api.get_audio_test.__wrapped__(11)

        payload = response.get_json()
        recommendation = payload["settings_recommendation"]
        evaluate.assert_not_called()
        self.assertEqual(status_code, 200)
        self.assertEqual(recommendation["id"], 41)
        self.assertTrue(recommendation["persisted"])
        self.assertEqual(recommendation["recommended"]["bass"], 5.5)
        self.assertEqual(payload["empirical_quality"]["overall_score"], 72.0)
        self.assertEqual(
            recommendation["profile_checksum"],
            load_genre_profiles().artifact_checksum,
        )
        self.assertEqual(response.get_json()["quality_profile_version"], "2026.09.1")
        self.assertEqual(response.get_json()["quality_profile_checksum"], "b" * 64)
        self.assertNotIn("settings_current_positions", response.get_json())
        statement = cursor.execute.call_args.args[0]
        self.assertIn("LEFT JOIN settings_recommendation", statement)
        self.assertIn("sr.user_id = a.user_id", statement)
        self.assertIn("r.quality_profile_version", statement)
        self.assertIn("r.quality_profile_checksum", statement)

    def test_visualization_is_served_from_owned_assessment_path(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        artifact = root / "7" / "11" / "recording_waveform.png"
        artifact.parent.mkdir(parents=True)
        artifact.write_bytes(b"real-matplotlib-png")
        connection = MagicMock()
        cursor = connection.cursor.return_value
        cursor.fetchone.return_value = {
            "artifact_path": "7/11/recording_waveform.png"
        }

        with api.app.test_request_context(
            "/api/audio-tests/11/visualizations/waveform"
        ), patch.object(api, "ANALYSIS_OUTPUT_DIR", str(root)), patch.object(
            api, "get_db", return_value=connection
        ):
            api.g.user_id = 7
            response = api.get_audio_visualization.__wrapped__(11, "waveform")

        response.direct_passthrough = False
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.mimetype, "image/png")
        self.assertEqual(response.get_data(), b"real-matplotlib-png")
        self.assertEqual(cursor.execute.call_args.args[1], (11, 7))
        response.close()

    def test_guest_analysis_returns_results_without_database_history(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        upload_root = root / "uploads"
        analysis_root = root / "analysis"
        dump = {
            "analysis_status": "completed",
            "analysis_purpose": "quality_evaluation",
            "upload": {
                "assessment_id": 99,
                "original_file_name": "guest.wav",
            },
            "analyzer_process": {"duration_seconds": 0.5},
            "analysis": _analyzer_result("passed"),
            "visualizations": {
                "waveform": "0/99/guest_waveform.png",
                "spectrogram": "0/99/guest_spectrogram.png",
            },
        }
        report_directory = analysis_root / "0" / "99"
        report_directory.mkdir(parents=True)
        png = b"\x89PNG\r\n\x1a\nserver-generated-report"
        (report_directory / "guest_waveform.png").write_bytes(png)
        (report_directory / "guest_spectrogram.png").write_bytes(png)

        with api.app.test_request_context(
            "/api/guest/audio-analysis",
            method="POST",
            data={
                "audio": (BytesIO(b"RIFF-test"), "guest.wav"),
                "duration_seconds": "2",
                "analysis_purpose": "quality_evaluation",
            },
            content_type="multipart/form-data",
        ), patch.object(
            api, "AUDIO_UPLOAD_DIR", str(upload_root)
        ), patch.object(
            api, "ANALYSIS_OUTPUT_DIR", str(analysis_root)
        ), patch.object(
            api, "audio_duration_seconds", return_value=2
        ), patch.object(
            api, "run_audio_analyzer", return_value=dump
        ), patch.object(
            api, "get_db", side_effect=AssertionError("guest history must not persist")
        ):
            response, status_code = api.create_guest_audio_analysis.__wrapped__()

        payload = response.get_json()
        self.assertEqual(status_code, 201)
        self.assertEqual(payload["status"], "Completed")
        self.assertTrue(payload["guest"])
        self.assertFalse(payload["persisted"])
        self.assertIsNone(payload["assessment_id"])
        self.assertIsNone(payload["analysis_dump"]["upload"]["assessment_id"])
        self.assertGreater(payload["score"], 0)
        self.assertNotIn("guest_import_receipt", payload)
        self.assertNotIn("settings_recommendation", payload)
        self.assertFalse(any(upload_root.rglob("*.wav")))
        self.assertFalse(any(analysis_root.rglob("*_analysis.json")))

    def test_guest_settings_upload_returns_five_non_persisted_targets(self):
        (response, status_code), upload_root = self._post_guest_audio(
            analysis_purpose="settings_suggestion"
        )

        payload = response.get_json()["settings_recommendation"]
        self.assertEqual(status_code, 201)
        self.assertIsNone(payload["id"])
        self.assertFalse(payload["persisted"])
        self.assertEqual(
            set(payload["recommended"]),
            {"volume", "bass", "treble", "sharpness", "flatness"},
        )
        self.assertIsInstance(payload["verification_token"], str)
        claims = api.jwt.decode(
            payload["verification_token"],
            api.JWT_SECRET,
            algorithms=["HS256"],
            audience=recommendation_service.GUEST_VERIFICATION_AUDIENCE,
        )
        self.assertEqual(set(claims), recommendation_service.GUEST_TOKEN_CLAIMS)
        self.assertNotIn("current_settings", claims)
        self.assertFalse(any(upload_root.rglob("*.wav")))

    def test_quality_evaluation_does_not_require_settings_fields(self):
        (response, status_code), _ = self._post_guest_audio(
            analysis_purpose="quality_evaluation"
        )

        self.assertEqual(status_code, 201)
        self.assertNotIn("settings_recommendation", response.get_json())

    def test_guest_verification_accepts_only_a_valid_initial_token(self):
        (initial_response, _), _ = self._post_guest_audio(
            analysis_purpose="settings_suggestion"
        )
        initial = initial_response.get_json()["settings_recommendation"]

        (verified_response, status_code), _ = self._post_guest_audio(
            analysis_purpose="settings_suggestion",
            current_settings=initial["recommended"],
            verification_token=initial["verification_token"],
        )

        verified = verified_response.get_json()["settings_recommendation"]
        self.assertEqual(status_code, 201)
        self.assertIsNone(verified["verification_token"])
        self.assertEqual(verified["before_score"], initial["original_score"])
        self.assertIn("score_change", verified)
        self.assertIn("verification_status", verified)

    def test_guest_verification_requires_the_initial_recommended_positions(self):
        (initial_response, _), _ = self._post_guest_audio(
            analysis_purpose="settings_suggestion"
        )
        initial = initial_response.get_json()["settings_recommendation"]
        changed = dict(initial["recommended"])
        changed["volume"] = 0.0 if changed["volume"] != 0.0 else 0.5

        (response, status_code), upload_root = self._post_guest_audio(
            analysis_purpose="settings_suggestion",
            current_settings=changed,
            verification_token=initial["verification_token"],
        )

        self.assertEqual(status_code, 400)
        self.assertIn("initial recommended positions", response.get_json()["error"])
        self.assertFalse(any(upload_root.rglob("*.wav")))

    def test_missing_genre_profile_retains_quality_and_marks_settings_unavailable(self):
        (response, status_code), _ = self._post_guest_audio(
            analysis_purpose="settings_suggestion",
            genre="classical",
        )

        payload = response.get_json()
        recommendation = payload["settings_recommendation"]
        self.assertEqual(status_code, 201)
        self.assertIsNotNone(payload["score"])
        self.assertEqual(recommendation["status"], "unavailable")
        self.assertIsNone(recommendation["verification_token"])
        self.assertTrue(
            all(value is None for value in recommendation["recommended"].values())
        )

    def test_expired_or_tampered_guest_verification_token_is_rejected(self):
        artifact = load_genre_profiles()
        expired = api.jwt.encode(
            {
                "kind": "guest_settings_verification",
                "genre": "rock",
                "scale": {"minimum": 0, "maximum": 10, "step": 0.5},
                "recommended_positions": {
                    "volume": 5,
                    "bass": 4,
                    "treble": 6,
                    "sharpness": 5,
                    "flatness": 5,
                },
                "before_score": 72.0,
                "profile_version": artifact.profile_version,
                "algorithm_version": ALGORITHM_VERSION,
                "initial_pass": True,
                "aud": "karaok-guest-settings-verification",
                "iat": datetime.now(timezone.utc) - timedelta(days=2),
                "exp": datetime.now(timezone.utc) - timedelta(days=1),
            },
            api.JWT_SECRET,
            algorithm="HS256",
        )
        for token in (expired, "tampered"):
            with self.subTest(token=token):
                result, upload_root = self._post_guest_audio(
                    analysis_purpose="settings_suggestion",
                    verification_token=token,
                )
                response, status_code = result
                self.assertEqual(status_code, 400)
                self.assertFalse(any(upload_root.rglob("*.wav")))

    def test_disabled_feature_rejects_only_settings_purpose_uploads(self):
        (settings_response, settings_status), upload_root = self._post_guest_audio(
            analysis_purpose="settings_suggestion",
            feature_enabled=False,
        )
        (quality_response, quality_status), _ = self._post_guest_audio(
            analysis_purpose="quality_evaluation",
            feature_enabled=False,
        )

        self.assertEqual(settings_status, 404)
        self.assertIn("error", settings_response.get_json())
        self.assertFalse(any(upload_root.rglob("*.wav")))
        self.assertEqual(quality_status, 201)
        self.assertNotIn("settings_recommendation", quality_response.get_json())


if __name__ == "__main__":
    unittest.main()
