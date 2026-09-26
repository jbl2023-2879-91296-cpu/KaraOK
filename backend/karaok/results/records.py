"""Records implementation."""

from __future__ import annotations

import json
import os
from typing import Any
from karaok.core.values import _nested_number
from karaok.core import recommendation_contracts as settings_recommendation_service

from karaok.core.database import get_db


def mark_audio_analysis_failed(
    assessment_id: int,
    upload_id: int,
    duration_seconds: float | None = None,
) -> None:
    conn = get_db()
    cursor = conn.cursor()
    try:
        cursor.execute(
            """UPDATE assessment
               SET assessment_status = 'Failed', result_status = 'Needs Improvement',
                   processing_time = %s
               WHERE assessment_id = %s""",
            (duration_seconds, assessment_id),
        )
        cursor.execute(
            "UPDATE audio_upload SET status = 'Failed' WHERE upload_id = %s",
            (upload_id,),
        )
        conn.commit()
    finally:
        cursor.close()
        conn.close()


def save_audio_analysis(
    assessment_id: int,
    upload_id: int,
    dump: dict[str, Any],
    *,
    summary: dict[str, Any],
    recommendation: settings_recommendation_service.SettingsRecommendation
    | None = None,
    recommendation_context: settings_recommendation_service.SuggestionContext
    | None = None,
) -> dict[str, Any]:
    if (recommendation is None) != (recommendation_context is None):
        raise ValueError(
            "recommendation and recommendation_context must be provided together"
        )
    quality_score = summary["score"]
    result_status = summary["status"]
    noise_level = summary["noise_level"]
    distortion_level = summary["distortion_level"]
    bass = summary["bass"]
    treble = summary["treble"]
    loudness = summary["loudness"]
    sharpness = summary["sharpness"]
    flatness = summary["flatness"]
    empirical = summary["empirical_quality"]
    processing_time = _nested_number(dump, "analyzer_process", "duration_seconds")
    empirical_status = str(empirical["overall_status"])
    worst_feature_status = str(empirical["worst_feature_status"])
    worst_features_json = json.dumps(
        empirical.get("worst_features", []),
        ensure_ascii=False,
        allow_nan=False,
    )
    empirical_details_json = json.dumps(
        empirical,
        ensure_ascii=False,
        allow_nan=False,
    )
    algorithm_version = str(empirical["algorithm_version"])
    quality_profile_version = str(empirical["quality_profile_version"])
    quality_profile_checksum = str(empirical["quality_profile_checksum"])
    reference_recording_count = empirical.get("reference_recording_count")
    visualizations = dump.get("visualizations")
    if not isinstance(visualizations, dict):
        raise RuntimeError("Analyzer visualizations are missing")
    waveform_path = visualizations.get("waveform")
    spectrogram_path = visualizations.get("spectrogram")
    if not isinstance(waveform_path, str) or not isinstance(spectrogram_path, str):
        raise RuntimeError("Analyzer visualizations are incomplete")

    conn = get_db()
    # The verification re-check needs named columns while holding the same
    # transaction that writes the child result.  The default connector cursor
    # returns tuples, which would make this security check silently unusable.
    cursor = conn.cursor(dictionary=True)
    recommendation_id = None
    recommendation_response = None
    try:
        if recommendation is not None and not recommendation_context.verification:
            context = recommendation_context
            if context.guest or context.user_id is None:
                raise ValueError("Authenticated persistence requires an owned context")
            if context.amplifier_profile_id is None:
                raise ValueError(
                    "Authenticated persistence requires an amplifier profile"
                )
            cursor.execute(
                """SELECT scale_min, scale_max, scale_step
                   FROM amplifier_profile
                   WHERE amplifier_profile_id = %s AND user_id = %s
                   FOR UPDATE""",
                (context.amplifier_profile_id, context.user_id),
            )
            locked_profile = cursor.fetchone()
            if locked_profile is None:
                raise ValueError("amplifier profile is no longer owned by this user")
            settings_recommendation_service.validate_profile_scale_snapshot(
                locked_profile,
                context.scale,
            )
        if recommendation is not None and recommendation_context.verification:
            context = recommendation_context
            if context.guest or context.user_id is None:
                raise ValueError("Authenticated persistence requires an owned context")
            if context.amplifier_profile_id is None:
                raise ValueError(
                    "Authenticated persistence requires an amplifier profile"
                )
            cursor.execute(
                """SELECT sr.recommendation_id, sr.genre, sr.original_score,
                          sr.recommended_positions, sr.algorithm_version,
                          sr.genre_profile_version, sr.genre_profile_checksum,
                          sr.scale_min, sr.scale_max, sr.scale_step,
                          sr.recommendation_status,
                          child.recommendation_id AS child_recommendation_id,
                          ap.last_positions AS amplifier_last_positions,
                          ap.scale_min AS profile_scale_min,
                          ap.scale_max AS profile_scale_max,
                          ap.scale_step AS profile_scale_step
                   FROM settings_recommendation sr
                   JOIN amplifier_profile ap
                     ON ap.amplifier_profile_id = sr.amplifier_profile_id
                    AND ap.user_id = sr.user_id
                   LEFT JOIN settings_recommendation child
                     ON child.parent_recommendation_id = sr.recommendation_id
                   WHERE sr.recommendation_id = %s AND sr.user_id = %s
                     AND sr.amplifier_profile_id = %s
                   FOR UPDATE""",
                (
                    context.verification_of,
                    context.user_id,
                    context.amplifier_profile_id,
                ),
            )
            parent = cursor.fetchone()
            if parent is None:
                raise ValueError(
                    "verification_of is no longer eligible for verification "
                    "with this amplifier profile"
                )
            if recommendation.status == "generated" and (
                parent.get("genre_profile_version") != recommendation.profile_version
                or parent.get("genre_profile_checksum")
                != recommendation.profile_checksum
            ):
                raise ValueError(
                    "verification_of profile provenance changed before verification "
                    "was saved"
                )
            settings_recommendation_service.validate_authenticated_verification_binding(
                parent,
                {
                    "last_positions": parent.get("amplifier_last_positions"),
                    "scale_min": parent["profile_scale_min"],
                    "scale_max": parent["profile_scale_max"],
                    "scale_step": parent["profile_scale_step"],
                },
                genre=context.genre,
                current=context.current,
                scale=context.scale,
                require_current_artifact=recommendation.profile_version is not None,
            )

        cursor.execute(
            """INSERT INTO audio_analysis_result
               (assessment_id, quality_score, noise_level, distortion_level,
                bass, treble, loudness, sharpness, flatness, empirical_status,
                worst_feature_status, worst_features, empirical_details,
                scoring_algorithm_version, quality_profile_version,
                quality_profile_checksum, reference_recording_count,
                waveform_path, spectrogram_path)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                       %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
            (
                assessment_id,
                quality_score,
                noise_level,
                distortion_level,
                bass,
                treble,
                loudness,
                sharpness,
                flatness,
                empirical_status,
                worst_feature_status,
                worst_features_json,
                empirical_details_json,
                algorithm_version,
                quality_profile_version,
                quality_profile_checksum,
                reference_recording_count,
                waveform_path,
                spectrogram_path,
            ),
        )
        if recommendation is not None:
            context = recommendation_context
            if context.guest or context.user_id is None:
                raise ValueError("Authenticated persistence requires an owned context")
            if context.amplifier_profile_id is None:
                raise ValueError("Authenticated persistence requires an amplifier profile")
            recommendation_data = recommendation.to_dict()
            original_score = (
                context.before_score if context.verification else quality_score
            )
            verification_score = quality_score if context.verification else None
            cursor.execute(
                """INSERT INTO settings_recommendation
                   (user_id, assessment_id, amplifier_profile_id,
                    parent_recommendation_id, genre, current_positions,
                    recommended_positions, adjustments, original_score,
                    verification_score, overall_confidence, algorithm_version,
                    scale_min, scale_max, scale_step,
                    genre_profile_version, genre_profile_checksum,
                    unavailable_message,
                    recommendation_status)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                           %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
                (
                    context.user_id,
                    assessment_id,
                    context.amplifier_profile_id,
                    context.verification_of,
                    recommendation.genre,
                    json.dumps(
                        recommendation_data["current"],
                        sort_keys=True,
                        separators=(",", ":"),
                        allow_nan=False,
                    ),
                    json.dumps(
                        recommendation_data["recommended"],
                        sort_keys=True,
                        separators=(",", ":"),
                        allow_nan=False,
                    ),
                    json.dumps(
                        recommendation_data["adjustments"],
                        sort_keys=True,
                        separators=(",", ":"),
                        allow_nan=False,
                    ),
                    original_score,
                    verification_score,
                    recommendation.overall_confidence,
                    recommendation.algorithm_version,
                    context.scale.minimum,
                    context.scale.maximum,
                    context.scale.step,
                    recommendation.profile_version,
                    recommendation.profile_checksum,
                    recommendation.message,
                    recommendation.status,
                ),
            )
            recommendation_id = cursor.lastrowid
            if context.verification:
                parent_status = (
                    "verified" if quality_score >= context.before_score else "reverted"
                )
                cursor.execute(
                    """UPDATE settings_recommendation
                       SET verification_score = %s, recommendation_status = %s
                       WHERE recommendation_id = %s AND user_id = %s
                         AND recommendation_status = 'applied'""",
                    (
                        quality_score,
                        parent_status,
                        context.verification_of,
                        context.user_id,
                    ),
                )
                if cursor.rowcount != 1:
                    raise ValueError(
                        "verification_of changed before verification was saved"
                    )
            recommendation_response = (
                settings_recommendation_service.recommendation_payload(
                    recommendation,
                    context,
                    score=quality_score,
                    recommendation_id=int(recommendation_id),
                    persisted=True,
                )
            )
        cursor.execute(
            """UPDATE assessment
               SET assessment_status = 'Completed', result_status = %s,
                   processing_time = %s, api_reference = %s
               WHERE assessment_id = %s""",
            (
                result_status,
                processing_time,
                f"/api/audio-uploads/{upload_id}/analysis-dump",
                assessment_id,
            ),
        )
        cursor.execute(
            "UPDATE audio_upload SET score = %s, status = %s WHERE upload_id = %s",
            (quality_score, result_status, upload_id),
        )
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        cursor.close()
        conn.close()
    if recommendation_response is not None:
        summary["settings_recommendation"] = recommendation_response
    return summary


def create_audio_upload_records(
    *, user_id: int, original_name: str, genre: str | None,
    duration: int, size: int, mime_type: str, stored_path: str,
    analysis_purpose: str,
) -> tuple[int, int]:
    """Create the processing assessment and upload in their original transaction."""
    conn = get_db()
    cursor = conn.cursor()
    try:
        cursor.execute(
            """INSERT INTO assessment
               (user_id, assessment_status, test_name,
                duration_seconds, result_status, analysis_purpose)
               VALUES (%s, 'Processing', %s, %s, 'Acceptable', %s)""",
            (
                user_id,
                original_name[:120],
                duration,
                analysis_purpose,
            ),
        )
        assessment_id = cursor.lastrowid
        cursor.execute(
            """INSERT INTO audio_upload
               (assessment_id, file_name, genre_name, score, status,
                size_bytes, mime_type)
               VALUES (%s, %s, %s, NULL, 'Acceptable', %s, %s)""",
            (
                assessment_id,
                original_name,
                genre,
                size,
                mime_type,
            ),
        )
        upload_id = cursor.lastrowid
        conn.commit()
    except Exception:
        conn.rollback()
        if os.path.exists(stored_path):
            os.remove(stored_path)
        raise
    finally:
        cursor.close()
        conn.close()
    return assessment_id, upload_id
