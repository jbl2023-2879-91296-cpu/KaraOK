"""Noise reliability contract across analysis, persistence, and saved reports."""
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import numpy as np
import pytest

from audio_engine import analyzer
from karaok.audio_pipeline.summary import summarize_audio_analysis
from karaok.results import assessments, presentation, records
from karaok.core.runtime import app

CASES = json.loads((Path(__file__).parent / "fixtures/backend_contract.json").read_text())["noise_reliability_cases"]


@pytest.mark.parametrize("separation", [5.99, 6.0, 6.01])
def test_analyzer_reliability_at_six_db_boundary(separation):
    # Keep quiet frames fixed and choose active RMS for an exact boundary.
    quiet = 0.01
    context = SimpleNamespace(
        frame_rms=np.array([quiet] * 20 + [quiet * 10 ** (separation / 20)] * 80),
        active_frames=np.array([False] * 20 + [True] * 80),
        config=SimpleNamespace(noise_percentile=15),
    )
    noise = analyzer.estimate_noise(context)
    assert isinstance(noise["reliable"], bool)
    assert noise["reliable"] is (separation >= analyzer.NOISE_RELIABILITY_MIN_SEPARATION_DB)


@pytest.mark.parametrize("case", CASES, ids=lambda case: case["name"])
def test_summary_and_persistence_preserve_noise_reliability(case):
    dump = {
        "analysis": {"noise": case["noise"]},
        "empirical_quality": {
            "overall_score": 88, "overall_status": "good", "worst_feature_status": "good",
            "algorithm_version": "1.0.0", "quality_profile_version": "saved",
            "quality_profile_checksum": "a" * 64,
        },
        "visualizations": {"waveform": "w.png", "spectrogram": "s.png"},
    }
    summary = summarize_audio_analysis(dump)
    assert summary["noise_reliable"] is case["noise_reliable"]
    connection = MagicMock()
    with patch.object(records, "get_db", return_value=connection):
        records.save_audio_analysis(11, 13, dump, summary=summary)
    insert = next(call for call in connection.cursor.return_value.execute.call_args_list
                  if "INSERT INTO audio_analysis_result" in call.args[0])
    assert "noise_reliable" in insert.args[0]
    assert insert.args[1][-1] is case["noise_reliable"]
    assert insert.args[0].count("%s") == len(insert.args[1])


@pytest.mark.parametrize("case", CASES, ids=lambda case: case["name"])
def test_saved_list_detail_and_dump_preserve_nullable_reliability(case):
    row = dict.fromkeys([
        "loudness", "bass", "treble", "sharpness", "flatness", "empirical_status",
        "worst_feature_status", "worst_features", "empirical_details",
        "scoring_algorithm_version", "quality_profile_version", "quality_profile_checksum",
        "reference_recording_count",
    ])
    row.update(assessment_id=11, file_name="saved.wav", quality_score=88,
               score=88, status="Acceptable", result_status="Acceptable",
               analysis_purpose="quality_evaluation", noise_level=-42, distortion_level=4)
    if case["noise_reliable"] is not None:
        # MySQL BOOLEAN is returned as an integer.
        row["noise_reliable"] = int(case["noise_reliable"])
    assert presentation._enrich_audio_test_row(dict(row))["noise_reliable"] is case["noise_reliable"]
    for route in ("list", "detail", "dump"):
        connection = MagicMock()
        cursor = connection.cursor.return_value
        cursor.fetchone.return_value = dict(row)
        cursor.fetchall.return_value = [dict(row)]
        with app.test_request_context(), patch.object(assessments, "get_db", return_value=connection):
            from flask import g
            g.user_id = 7
            if route == "list":
                payload = assessments.get_audio_tests.__wrapped__().get_json()[0]
            elif route == "detail":
                payload = assessments.get_audio_test.__wrapped__(11)[0].get_json()
            else:
                payload = assessments.get_audio_analysis_dump.__wrapped__(13).get_json()
        assert "r.noise_reliable" in cursor.execute.call_args.args[0]
        actual = payload["analysis"]["noise"]["reliable"] if route == "dump" else payload["noise_reliable"]
        assert actual is case["noise_reliable"]


@pytest.mark.parametrize("case", CASES, ids=lambda case: case["name"])
def test_authenticated_upload_response_preserves_reliability(case, tmp_path):
    from io import BytesIO
    from flask import g
    from karaok.audio_pipeline import pipeline

    dump = {
        "analysis": {"noise": case["noise"]},
        "empirical_quality": {"overall_score": 88, "overall_status": "good"},
    }
    summary = summarize_audio_analysis(dump)
    with app.test_request_context(
        "/api/audio-uploads", method="POST",
        data={"audio": (BytesIO(b"RIFF-test"), "test.wav"), "duration_seconds": "2"},
        content_type="multipart/form-data",
    ), patch.object(pipeline, "AUDIO_UPLOAD_DIR", str(tmp_path)), patch.object(
        pipeline, "audio_duration_seconds", return_value=2
    ), patch.object(pipeline, "create_audio_upload_records", return_value=(11, 13)), patch.object(
        pipeline, "run_audio_analyzer", return_value=dump
    ), patch.object(pipeline, "persist_audio_analysis", return_value=summary), patch.object(pipeline, "audit"):
        g.user_id = 7
        response, status = pipeline.create_audio_upload.__wrapped__()
    assert status == 201
    assert response.get_json()["noise_reliable"] is case["noise_reliable"]
