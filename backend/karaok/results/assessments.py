"""Assessments implementation."""

from __future__ import annotations

from flask import g
from flask import jsonify
from karaok.auth.access import require_auth
from karaok.core.artifacts import cleanup_audio_artifacts
from karaok.core.audit import audit
from karaok.core.config import ALLOWED_ANALYSIS_PURPOSES
from karaok.core.database import get_db
from karaok.core.runtime import app
from karaok.core.thresholds import load_thresholds
from karaok.core.validation import bounded_number
from karaok.core.validation import clean_text
from karaok.core.validation import json_body
from karaok.core import recommendation_contracts as settings_recommendation_service
from karaok.results.presentation import _attach_stored_recommendation
from karaok.results.presentation import _enrich_audio_test_row


VALID_STATUSES = {"Acceptable", "Needs Improvement", "Problematic"}


SETTINGS_RECOMMENDATION_SELECT_COLUMNS = """
    sr.recommendation_id AS settings_recommendation_id,
    sr.assessment_id AS settings_assessment_id,
    sr.amplifier_profile_id AS settings_amplifier_profile_id,
    sr.parent_recommendation_id AS settings_parent_recommendation_id,
    sr.genre AS settings_genre,
    sr.current_positions AS settings_current_positions,
    sr.recommended_positions AS settings_recommended_positions,
    sr.adjustments AS settings_adjustments,
    sr.original_score AS settings_original_score,
    sr.verification_score AS settings_verification_score,
    sr.overall_confidence AS settings_overall_confidence,
    sr.algorithm_version AS settings_algorithm_version,
    sr.genre_profile_version AS settings_genre_profile_version,
    sr.genre_profile_checksum AS settings_genre_profile_checksum,
    sr.unavailable_message AS settings_unavailable_message,
    sr.recommendation_status AS settings_recommendation_status,
    sr.created_at AS settings_created_at,
    sr.applied_at AS settings_applied_at,
    sr.scale_min AS settings_scale_min,
    sr.scale_max AS settings_scale_max,
    sr.scale_step AS settings_scale_step
""".strip()


@require_auth("user")
def get_audio_tests():
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        f"""SELECT a.assessment_id AS id, a.test_name,
                  r.quality_score AS score, r.noise_level,
                  r.distortion_level, r.bass, r.treble, r.loudness,
                  r.sharpness, r.flatness, r.empirical_status,
                  r.worst_feature_status, r.worst_features,
                  r.empirical_details, r.scoring_algorithm_version,
                  r.quality_profile_version, r.quality_profile_checksum,
                  r.reference_recording_count, a.result_status AS status,
                  a.assessment_status, a.analysis_purpose, a.duration_seconds,
                  a.assessment_date AS created_at,
                  {SETTINGS_RECOMMENDATION_SELECT_COLUMNS}
           FROM assessment a
           LEFT JOIN audio_analysis_result r
             ON r.assessment_id = a.assessment_id
           LEFT JOIN settings_recommendation sr
             ON sr.assessment_id = a.assessment_id AND sr.user_id = a.user_id
           LEFT JOIN amplifier_profile ap
             ON ap.amplifier_profile_id = sr.amplifier_profile_id
            AND ap.user_id = a.user_id
           WHERE a.user_id = %s
           ORDER BY a.assessment_date DESC""",
        (g.user_id,),
    )
    rows = [
        _attach_stored_recommendation(_enrich_audio_test_row(row))
        for row in cursor.fetchall()
    ]
    cursor.close()
    conn.close()
    return jsonify(rows)


@require_auth("user")
def get_audio_test(test_id: int):
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        f"""SELECT a.assessment_id AS id, a.test_name,
                  r.quality_score AS score, r.noise_level,
                  r.distortion_level, r.bass, r.treble, r.loudness,
                  r.sharpness, r.flatness, r.empirical_status,
                  r.worst_feature_status, r.worst_features,
                  r.empirical_details, r.scoring_algorithm_version,
                  r.quality_profile_version, r.quality_profile_checksum,
                  r.reference_recording_count, a.result_status AS status,
                  a.assessment_status, a.analysis_purpose, a.duration_seconds,
                  a.assessment_date AS created_at,
                  {SETTINGS_RECOMMENDATION_SELECT_COLUMNS}
           FROM assessment a
           LEFT JOIN audio_analysis_result r
             ON r.assessment_id = a.assessment_id
           LEFT JOIN settings_recommendation sr
             ON sr.assessment_id = a.assessment_id AND sr.user_id = a.user_id
           LEFT JOIN amplifier_profile ap
             ON ap.amplifier_profile_id = sr.amplifier_profile_id
            AND ap.user_id = a.user_id
           WHERE a.assessment_id = %s AND a.user_id = %s""",
        (test_id, g.user_id),
    )
    row = cursor.fetchone()
    cursor.close()
    conn.close()
    if not row:
        return jsonify({"error": "Not found"}), 404
    return jsonify(_attach_stored_recommendation(_enrich_audio_test_row(row))), 200


@require_auth("user")
def create_audio_test():
    data = json_body()
    test_name = clean_text(data.get("test_name"), "test_name", 1, 120)
    score = int(bounded_number(data.get("score"), "score", 0, 100))
    noise = bounded_number(data.get("noise_level", 0), "noise_level", -200, 200)
    distortion = bounded_number(data.get("distortion_level", 0), "distortion_level", 0, 100)
    duration = int(bounded_number(data.get("duration_seconds", 0), "duration_seconds", 0, 86400))
    status = data.get("status", "Acceptable")
    analysis_purpose = data.get("analysis_purpose", "quality_evaluation")
    if analysis_purpose not in ALLOWED_ANALYSIS_PURPOSES:
        raise ValueError("analysis_purpose is invalid")
    if status not in VALID_STATUSES:
        raise ValueError("status is invalid")
    thresholds = load_thresholds()
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        """INSERT INTO assessment
           (user_id, test_name, result_status, duration_seconds,
            assessment_status, analysis_purpose)
           VALUES (%s, %s, %s, %s, 'Completed', %s)""",
        (g.user_id, test_name, status, duration, analysis_purpose),
    )
    test_id = cursor.lastrowid
    cursor.execute(
        """INSERT INTO audio_analysis_result
           (assessment_id, quality_score, noise_level, distortion_level,
            scoring_algorithm_version, quality_profile_version,
            quality_profile_checksum)
           VALUES (%s, %s, %s, %s, %s, %s, %s)""",
        (
            test_id,
            score,
            noise,
            distortion,
            thresholds["algorithm_version"],
            thresholds["quality_profile_version"],
            thresholds["artifact_checksum"],
        ),
    )
    conn.commit()
    cursor.close()
    conn.close()
    audit("audio_test_created", "success", user_id=g.user_id, resource_type="audio_test", resource_id=test_id)
    return jsonify({"id": test_id, "test_name": test_name, "score": score}), 201


@require_auth("user")
def delete_audio_test(test_id: int):
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        """SELECT assessment_id FROM assessment
           WHERE assessment_id = %s AND user_id = %s
           FOR UPDATE""",
        (test_id, g.user_id),
    )
    assessment = cursor.fetchone()
    if not assessment:
        cursor.close()
        conn.close()
        return jsonify({"error": "Not found"}), 404
    cursor.execute(
        "DELETE FROM assessment WHERE assessment_id = %s AND user_id = %s",
        (test_id, g.user_id),
    )
    conn.commit()
    cursor.close()
    conn.close()
    try:
        cleanup_audio_artifacts(g.user_id, test_id)
    except (OSError, RuntimeError):
        app.logger.exception("Deleted assessment artifact cleanup failed")
    audit("audio_test_deleted", "success", user_id=g.user_id, resource_type="audio_test", resource_id=test_id)
    return jsonify({"message": "Deleted"})


@require_auth("user")
def get_audio_uploads():
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        f"""SELECT au.upload_id AS id, au.file_name,
                  au.genre_name AS genre, au.score, au.status,
                  au.size_bytes, au.mime_type, a.duration_seconds,
                  a.analysis_purpose, au.created_at,
                  r.quality_profile_version, r.quality_profile_checksum,
                  {SETTINGS_RECOMMENDATION_SELECT_COLUMNS}
           FROM audio_upload au
           JOIN assessment a ON a.assessment_id = au.assessment_id
           LEFT JOIN audio_analysis_result r
             ON r.assessment_id = a.assessment_id
           LEFT JOIN settings_recommendation sr
             ON sr.assessment_id = a.assessment_id AND sr.user_id = a.user_id
           LEFT JOIN amplifier_profile ap
             ON ap.amplifier_profile_id = sr.amplifier_profile_id
            AND ap.user_id = a.user_id
           WHERE a.user_id = %s ORDER BY au.created_at DESC""",
        (g.user_id,),
    )
    rows = [_attach_stored_recommendation(row) for row in cursor.fetchall()]
    cursor.close()
    conn.close()
    return jsonify(rows)


@require_auth("user")
def get_audio_analysis_dump(upload_id: int):
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        f"""SELECT au.assessment_id, au.file_name,
                  a.analysis_purpose, a.assessment_status, a.result_status,
                  r.quality_score, r.noise_level, r.distortion_level,
                  r.bass, r.treble, r.loudness, r.sharpness, r.flatness,
                  r.empirical_status, r.worst_feature_status,
                  r.worst_features, r.empirical_details,
                  r.scoring_algorithm_version, r.quality_profile_version,
                  r.quality_profile_checksum, r.reference_recording_count,
                  {SETTINGS_RECOMMENDATION_SELECT_COLUMNS}
           FROM audio_upload au
           JOIN assessment a ON a.assessment_id = au.assessment_id
           LEFT JOIN audio_analysis_result r
             ON r.assessment_id = a.assessment_id
           LEFT JOIN settings_recommendation sr
             ON sr.assessment_id = a.assessment_id AND sr.user_id = a.user_id
           LEFT JOIN amplifier_profile ap
             ON ap.amplifier_profile_id = sr.amplifier_profile_id
            AND ap.user_id = a.user_id
           WHERE au.upload_id = %s AND a.user_id = %s""",
        (upload_id, g.user_id),
    )
    upload_record = cursor.fetchone()
    cursor.close()
    conn.close()
    if not upload_record or upload_record["assessment_id"] is None:
        return jsonify({"error": "Analysis output not found"}), 404
    stored_quality = _enrich_audio_test_row(
        {
            "score": upload_record["quality_score"],
            "status": upload_record["result_status"],
            "loudness": upload_record["loudness"],
            "bass": upload_record["bass"],
            "treble": upload_record["treble"],
            "sharpness": upload_record["sharpness"],
            "flatness": upload_record["flatness"],
            "empirical_status": upload_record["empirical_status"],
            "worst_feature_status": upload_record["worst_feature_status"],
            "worst_features": upload_record["worst_features"],
            "empirical_details": upload_record["empirical_details"],
            "scoring_algorithm_version": upload_record[
                "scoring_algorithm_version"
            ],
            "quality_profile_version": upload_record["quality_profile_version"],
            "quality_profile_checksum": upload_record[
                "quality_profile_checksum"
            ],
            "reference_recording_count": upload_record[
                "reference_recording_count"
            ],
        }
    )
    if stored_quality["score"] is None:
        return jsonify({"error": "Analysis output not found"}), 404
    empirical = stored_quality["empirical_quality"]

    response_data = {
        "dump_schema_version": 1,
        "analysis_status": "completed",
        "analysis_purpose": upload_record["analysis_purpose"],
        "upload": {
            "assessment_id": upload_record["assessment_id"],
            "original_file_name": upload_record["file_name"],
        },
        "analysis": {
            "noise": {"noise_dbfs": upload_record["noise_level"]},
            "distortion": {
                "estimated_score": upload_record["distortion_level"]
            },
            "bass": {"energy_percentage": upload_record["bass"]},
            "treble": {"energy_percentage": upload_record["treble"]},
            "loudness": {"integrated_lufs": upload_record["loudness"]},
            "sharpness": {"normalized_score": upload_record["sharpness"]},
            "flatness": {"mean": upload_record["flatness"]},
            "quality_assessment": {
                "status": stored_quality["status"],
                "empirical_status": empirical.get("overall_status"),
                "worst_feature_status": empirical.get("worst_feature_status"),
                "worst_features": empirical["worst_features"],
            },
        },
        "empirical_quality": empirical,
        "scoring_algorithm_version": stored_quality["scoring_algorithm_version"],
        "quality_profile_version": stored_quality["quality_profile_version"],
        "quality_profile_checksum": stored_quality["quality_profile_checksum"],
        "reference_recording_count": stored_quality["reference_recording_count"],
    }
    if upload_record["analysis_purpose"] == "settings_suggestion":
        response_data["settings_recommendation"] = (
            settings_recommendation_service.stored_recommendation_payload(
                upload_record
            )
        )
    return jsonify(response_data)
