"""Pipeline implementation."""

from __future__ import annotations

from . import recommendations as settings_recommendation_service
from .execution import AudioAnalyzerExecutionError
from .execution import _execute_analyzer_command
from .execution import _process_text
from .execution import _run_audio_analyzer
from .execution import run_audio_analyzer
from .recommendations import GENRE_ARTIFACT_UNAVAILABLE_MESSAGE
from .recommendations import GUEST_TOKEN_CLAIMS
from .recommendations import GUEST_VERIFICATION_AUDIENCE
from .recommendations import GUEST_VERIFICATION_KIND
from .recommendations import MISSING_GENRE_PROFILE_MESSAGE
from .recommendations import _unavailable_recommendation
from .recommendations import build_recommendation
from .recommendations import issue_guest_verification_token
from .recommendations import parse_guest_verification_token
from .recommendations import parse_suggestion_form
from .summary import _analysis_safety_signals
from .summary import _empirical_feature_values
from .summary import _score_analyzer_output
from .summary import summarize_audio_analysis
from .uploads import AudioDurationError
from .uploads import MIDI_RENDERED_AUDIO_MESSAGE
from .uploads import audio_duration_seconds
from .visualizations import _guest_visualization_images
from .visualizations import _visualization_paths
from flask import g
from flask import jsonify
from flask import request
from karaok.auth.access import require_auth
from karaok.core.validation import clean_text
from karaok.core.config import ALLOWED_ANALYSIS_PURPOSES
from karaok.core.config import ALLOWED_AUDIO_EXTENSIONS
from karaok.core.config import AUDIO_UPLOAD_DIR
from karaok.core.config import MAX_AUDIO_BYTES
from karaok.core.config import SETTINGS_RECOMMENDATIONS_ENABLED
from karaok.core.artifacts import _remove_temporary_audio
from karaok.core.artifacts import cleanup_audio_artifacts
from karaok.core.audit import audit
from karaok.core.runtime import app
from karaok.core.runtime import limiter
from karaok.core.time import utcnow
from karaok.core.values import _nested_number
from karaok.results.records import create_audio_upload_records
from karaok.results.records import mark_audio_analysis_failed
from karaok.results.records import save_audio_analysis
from typing import Any
from werkzeug.utils import secure_filename
import mimetypes
import os
import secrets
import uuid


def persist_audio_analysis(
    assessment_id: int,
    upload_id: int,
    dump: dict[str, Any],
    *,
    recommendation: settings_recommendation_service.SettingsRecommendation
    | None = None,
    recommendation_context: settings_recommendation_service.SuggestionContext
    | None = None,
) -> dict[str, Any]:
    if (recommendation is None) != (recommendation_context is None):
        raise ValueError(
            "recommendation and recommendation_context must be provided together"
        )
    summary = summarize_audio_analysis(dump)
    return save_audio_analysis(
        assessment_id, upload_id, dump, summary=summary,
        recommendation=recommendation, recommendation_context=recommendation_context,
    )


@limiter.limit("3 per hour")
def create_guest_audio_analysis():
    """Analyze one client-limited guest upload without saving business records."""
    upload = request.files.get("audio")
    if upload is None or not upload.filename:
        return jsonify(
            {"error": "A multipart audio file is required in the 'audio' field"}
        ), 400
    original_name = secure_filename(upload.filename)
    extension = original_name.rsplit(".", 1)[-1].lower() if "." in original_name else ""
    if extension in {"mid", "midi"}:
        return jsonify({"error": MIDI_RENDERED_AUDIO_MESSAGE}), 400
    if extension not in ALLOWED_AUDIO_EXTENSIONS:
        return jsonify({"error": "Unsupported audio format"}), 415
    mime_type = (
        mimetypes.guess_type(original_name)[0]
        or upload.mimetype
        or "application/octet-stream"
    )[:100]
    try:
        client_duration = int(request.form.get("duration_seconds", "0"))
    except ValueError:
        return jsonify({"error": "duration_seconds must be an integer"}), 400
    if client_duration < 1:
        return jsonify({"error": "duration_seconds is required"}), 400
    analysis_purpose = request.form.get("analysis_purpose", "quality_evaluation")
    if analysis_purpose not in ALLOWED_ANALYSIS_PURPOSES:
        return jsonify({"error": "analysis_purpose is invalid"}), 400
    suggestion_context = None
    if analysis_purpose == "settings_suggestion":
        if not SETTINGS_RECOMMENDATIONS_ENABLED:
            return jsonify({"error": "Not found"}), 404
        try:
            suggestion_context = settings_recommendation_service.parse_suggestion_form(
                request.form,
                guest=True,
                user_id=None,
            )
        except ValueError as error:
            return jsonify({"error": str(error)}), 400

    guest_dir = os.path.join(AUDIO_UPLOAD_DIR, "_guest")
    os.makedirs(guest_dir, exist_ok=True)
    stored_name = f"{uuid.uuid4().hex}.{extension}"
    stored_path = os.path.abspath(os.path.join(guest_dir, stored_name))
    if os.path.commonpath([AUDIO_UPLOAD_DIR, stored_path]) != AUDIO_UPLOAD_DIR:
        return jsonify({"error": "Invalid upload path"}), 400
    upload.save(stored_path)
    size = os.path.getsize(stored_path)
    if size == 0 or size > MAX_AUDIO_BYTES:
        os.remove(stored_path)
        return jsonify({"error": "Audio file is empty or exceeds the 25 MB limit"}), 413
    try:
        duration = audio_duration_seconds(stored_path)
    except AudioDurationError as error:
        os.remove(stored_path)
        return jsonify({"error": str(error)}), 422
    except Exception:
        os.remove(stored_path)
        return jsonify({"error": "Audio file is corrupted or unreadable"}), 422

    work_id = secrets.randbelow(2_000_000_000) + 1
    visualization_images: dict[str, str] = {}
    try:
        try:
            analysis_dump = run_audio_analyzer(
                stored_path,
                user_id=0,
                assessment_id=work_id,
                original_name=original_name,
                analysis_purpose=analysis_purpose,
            )
            analysis_summary = summarize_audio_analysis(analysis_dump)
            settings_payload = None
            if suggestion_context is not None:
                recommendation = settings_recommendation_service.build_recommendation(
                    analysis_summary,
                    suggestion_context,
                    verification=suggestion_context.verification,
                )
                verification_token = None
                if not suggestion_context.verification and recommendation.status == "generated":
                    verification_token = (
                        settings_recommendation_service.issue_guest_verification_token(
                            recommendation,
                            suggestion_context.scale,
                            before_score=analysis_summary["score"],
                        )
                    )
                settings_payload = (
                    settings_recommendation_service.recommendation_payload(
                        recommendation,
                        suggestion_context,
                        score=analysis_summary["score"],
                        recommendation_id=None,
                        persisted=False,
                        verification_token=verification_token,
                    )
                )
            visualization_images = _guest_visualization_images(analysis_dump)
            status = "Completed"
        except AudioAnalyzerExecutionError as error:
            analysis_dump = error.dump
            analysis_summary = None
            settings_payload = None
            status = "Failed"
        except Exception:
            app.logger.exception("Guest audio analysis failed")
            analysis_dump = {
                "dump_schema_version": 1,
                "analysis_status": "failed",
                "analysis_purpose": analysis_purpose,
                "upload": {
                    "assessment_id": None,
                    "original_file_name": original_name,
                },
                "analysis": None,
                "error": "Audio analysis failed unexpectedly",
            }
            analysis_summary = None
            settings_payload = None
            status = "Failed"
    finally:
        try:
            cleanup_audio_artifacts(0, work_id, stored_path)
        except (OSError, RuntimeError):
            app.logger.exception("Transient guest audio cleanup failed")

    upload_details = analysis_dump.get("upload")
    if isinstance(upload_details, dict):
        upload_details["assessment_id"] = None
    response_data = {
        "id": None,
        "assessment_id": None,
        "guest": True,
        "persisted": False,
        "file_name": original_name,
        "duration_seconds": duration,
        "size_bytes": size,
        "mime_type": mime_type,
        "status": status,
        "result_status": (
            analysis_summary["status"] if analysis_summary else "Failed"
        ),
        "score": analysis_summary["score"] if analysis_summary else None,
        "noise_level": (
            analysis_summary["noise_level"] if analysis_summary else None
        ),
        "distortion_level": (
            analysis_summary["distortion_level"] if analysis_summary else None
        ),
        "bass": analysis_summary["bass"] if analysis_summary else None,
        "treble": analysis_summary["treble"] if analysis_summary else None,
        "loudness": analysis_summary["loudness"] if analysis_summary else None,
        "sharpness": (
            analysis_summary["sharpness"] if analysis_summary else None
        ),
        "flatness": analysis_summary["flatness"] if analysis_summary else None,
        "empirical_quality": (
            analysis_summary["empirical_quality"] if analysis_summary else None
        ),
        "analysis_purpose": analysis_purpose,
        "analysis_dump": analysis_dump,
        "visualizations": visualization_images,
        "created_at": utcnow().isoformat(),
    }
    if settings_payload is not None:
        response_data["settings_recommendation"] = settings_payload
    return jsonify(response_data), 201


@require_auth("user")
def create_audio_upload():
    upload = request.files.get("audio")
    if upload is None or not upload.filename:
        return jsonify({"error": "A multipart audio file is required in the 'audio' field"}), 400
    original_name = secure_filename(upload.filename)
    extension = original_name.rsplit(".", 1)[-1].lower() if "." in original_name else ""
    if extension in {"mid", "midi"}:
        return jsonify({"error": MIDI_RENDERED_AUDIO_MESSAGE}), 400
    if extension not in ALLOWED_AUDIO_EXTENSIONS:
        return jsonify({"error": "Unsupported audio format"}), 415
    mime_type = (
        mimetypes.guess_type(original_name)[0]
        or upload.mimetype
        or "application/octet-stream"
    )[:100]
    try:
        client_duration = int(request.form.get("duration_seconds", "0"))
    except ValueError:
        return jsonify({"error": "duration_seconds must be an integer"}), 400
    if client_duration < 1:
        return jsonify({"error": "duration_seconds is required"}), 400
    genre_value = request.form.get("genre")
    genre = clean_text(genre_value, "genre", 2, 50) if genre_value else None
    analysis_purpose = request.form.get("analysis_purpose", "quality_evaluation")
    if analysis_purpose not in ALLOWED_ANALYSIS_PURPOSES:
        return jsonify({"error": "analysis_purpose is invalid"}), 400
    suggestion_context = None
    if analysis_purpose == "settings_suggestion":
        if not SETTINGS_RECOMMENDATIONS_ENABLED:
            return jsonify({"error": "Not found"}), 404
        try:
            suggestion_context = settings_recommendation_service.parse_suggestion_form(
                request.form,
                guest=False,
                user_id=g.user_id,
            )
            genre = suggestion_context.genre
        except ValueError as error:
            return jsonify({"error": str(error)}), 400

    user_dir = os.path.join(AUDIO_UPLOAD_DIR, str(g.user_id))
    os.makedirs(user_dir, exist_ok=True)
    stored_name = f"{uuid.uuid4().hex}.{extension}"
    stored_path = os.path.abspath(os.path.join(user_dir, stored_name))
    if os.path.commonpath([AUDIO_UPLOAD_DIR, stored_path]) != AUDIO_UPLOAD_DIR:
        return jsonify({"error": "Invalid upload path"}), 400
    upload.save(stored_path)
    size = os.path.getsize(stored_path)
    if size == 0 or size > MAX_AUDIO_BYTES:
        os.remove(stored_path)
        return jsonify({"error": "Audio file is empty or exceeds the 25 MB limit"}), 413
    try:
        duration = audio_duration_seconds(stored_path)
    except AudioDurationError as error:
        os.remove(stored_path)
        return jsonify({"error": str(error)}), 422
    except Exception:
        os.remove(stored_path)
        return jsonify({"error": "Audio file is corrupted or unreadable"}), 422

    assessment_id, upload_id = create_audio_upload_records(
        user_id=g.user_id, original_name=original_name, genre=genre,
        duration=duration, size=size, mime_type=mime_type, stored_path=stored_path,
        analysis_purpose=analysis_purpose,
    )
    retryable_settings_failure = False
    try:
        analysis_dump = run_audio_analyzer(
            stored_path,
            user_id=g.user_id,
            assessment_id=assessment_id,
            original_name=original_name,
            analysis_purpose=analysis_purpose,
        )
        recommendation = None
        if suggestion_context is not None:
            recommendation = settings_recommendation_service.build_recommendation(
                summarize_audio_analysis(analysis_dump),
                suggestion_context,
                verification=suggestion_context.verification,
            )
        analysis_summary = persist_audio_analysis(
            assessment_id,
            upload_id,
            analysis_dump,
            recommendation=recommendation,
            recommendation_context=suggestion_context,
        )
        status = "Completed"
        audit_result = "success"
    except AudioAnalyzerExecutionError as error:
        analysis_dump = error.dump
        analysis_summary = None
        processing_time = _nested_number(
            analysis_dump,
            "analyzer_process",
            "duration_seconds",
        )
        mark_audio_analysis_failed(assessment_id, upload_id, processing_time)
        status = "Failed"
        audit_result = "failure"
    except Exception as error:
        app.logger.exception("Uploaded audio analysis failed")
        retryable_settings_failure = (
            suggestion_context is not None
            and isinstance(locals().get("analysis_dump"), dict)
            and analysis_dump.get("analysis_status") == "completed"
        )
        failure_dump = {
            "dump_schema_version": 1,
            "analysis_status": "failed",
            "analysis_purpose": analysis_purpose,
            "upload": {
                "assessment_id": assessment_id,
                "original_file_name": original_name,
            },
            "analysis": None,
            "error": str(error).strip() or type(error).__name__,
        }
        mark_audio_analysis_failed(assessment_id, upload_id)
        analysis_dump = failure_dump
        analysis_summary = None
        status = "Failed"
        audit_result = "failure"
    finally:
        try:
            _remove_temporary_audio(stored_path)
            if status != "Completed":
                cleanup_audio_artifacts(g.user_id, assessment_id)
        except (OSError, RuntimeError):
            app.logger.exception("Transient uploaded audio cleanup failed")

    audit(
        "audio_upload_analyzed",
        audit_result,
        user_id=g.user_id,
        resource_type="audio_upload",
        resource_id=upload_id,
        details=f"purpose={analysis_purpose}; status={status}",
    )
    if retryable_settings_failure:
        return (
            jsonify(
                {
                    "error": "Settings recommendation could not be saved. Please retry.",
                    "retryable": True,
                    "assessment_id": assessment_id,
                    "upload_id": upload_id,
                }
            ),
            503,
        )
    response_data = {
        "id": upload_id,
        "assessment_id": assessment_id,
        "file_name": original_name,
        "genre": genre,
        "duration_seconds": duration,
        "size_bytes": size,
        "mime_type": mime_type,
        "status": status,
        "result_status": (
            analysis_summary["status"] if analysis_summary else "Failed"
        ),
        "score": analysis_summary["score"] if analysis_summary else None,
        "noise_level": (
            analysis_summary["noise_level"] if analysis_summary else None
        ),
        "distortion_level": (
            analysis_summary["distortion_level"] if analysis_summary else None
        ),
        "bass": analysis_summary["bass"] if analysis_summary else None,
        "treble": analysis_summary["treble"] if analysis_summary else None,
        "loudness": analysis_summary["loudness"] if analysis_summary else None,
        "sharpness": (
            analysis_summary["sharpness"] if analysis_summary else None
        ),
        "flatness": analysis_summary["flatness"] if analysis_summary else None,
        "empirical_quality": (
            analysis_summary["empirical_quality"] if analysis_summary else None
        ),
        "analysis_purpose": analysis_purpose,
        "analysis_dump_url": f"/api/audio-uploads/{upload_id}/analysis-dump",
        "visualizations": {
            kind: f"/api/audio-tests/{assessment_id}/visualizations/{kind}"
            for kind in ("waveform", "spectrogram")
        }
        if analysis_summary
        else {},
        "analysis_dump": analysis_dump,
    }
    if analysis_summary and analysis_summary.get("settings_recommendation") is not None:
        response_data["settings_recommendation"] = analysis_summary[
            "settings_recommendation"
        ]
    return jsonify(response_data), 201
