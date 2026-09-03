from __future__ import annotations

import base64
import binascii
from datetime import datetime, timedelta, timezone
from functools import wraps
import json
import math
import mimetypes
import os
from pathlib import Path
import re
import secrets
import signal
import shutil
import smtplib
import subprocess
import sys
import time
import uuid
from email.message import EmailMessage
from typing import Any, Callable

from argon2.exceptions import InvalidHashError, VerifyMismatchError
from flask import Flask, g, jsonify, request, send_file
import jwt
from mutagen import File as MutagenFile
from mysql.connector import Error, IntegrityError
from werkzeug.exceptions import HTTPException
from werkzeug.middleware.proxy_fix import ProxyFix
from werkzeug.utils import secure_filename

from audio_thresholds import evaluate_features, load_thresholds

from .common.validation import bounded_number, clean_text, json_body
from .config import (
    ACCESS_TOKEN_MINUTES,
    ALLOWED_ANALYSIS_PURPOSES,
    ALLOWED_AUDIO_EXTENSIONS,
    ANALYSIS_OUTPUT_DIR,
    ANALYZER_COMPLETED_EXIT_CODES,
    AUDIO_ANALYSIS_TIMEOUT_SECONDS,
    AUDIO_ANALYZER_PATH,
    AUDIO_ANALYZER_SETTINGS_PATH,
    AUDIO_UPLOAD_DIR,
    DEV_MODE,
    EXPOSE_REGISTRATION_OTP,
    JWT_ISSUER,
    JWT_SECRET,
    MAX_AUDIO_BYTES,
    MAX_AUDIO_SECONDS,
    MAX_PROFILE_IMAGE_BYTES,
    OTP_MINUTES,
    REFRESH_TOKEN_DAYS,
    SMTP_FROM,
    SMTP_HOST,
    SMTP_PASSWORD,
    SMTP_PORT,
    SMTP_USERNAME,
    SETTINGS_RECOMMENDATIONS_ENABLED,
    TRUST_PROXY,
)
from .infrastructure.database import get_db
from .extensions import configure_extensions
from .modules.assessments.routes import blueprint as assessments_routes
from .modules.admin_data.routes import blueprint as admin_data_routes
from .modules.audio_analysis.routes import blueprint as audio_analysis_routes
from .modules.audit.routes import blueprint as audit_routes
from .modules.auth.routes import blueprint as auth_routes
from .modules.system.routes import blueprint as system_routes
from .modules.settings_recommendations.routes import (
    blueprint as settings_recommendation_routes,
)
from .modules.settings_recommendations import service as settings_recommendation_service
from .modules.users.routes import blueprint as users_routes
from .security.password_service import (
    EMAIL_RE,
    clean_email,
    generate_temporary_password,
    password_hasher,
    token_hash,
    validate_password,
)
from .security.headers import apply_security_headers
from .security.token_service import (
    issue_access_token as create_access_token,
    token_precedes_security_update,
)
from .security.upload_policy import ensure_within_root, resolve_within_root

app = Flask(__name__)
if TRUST_PROXY:
    # The production service accepts traffic only from one local Nginx proxy.
    app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)
limiter = configure_extensions(app)

app.config["MAX_CONTENT_LENGTH"] = MAX_AUDIO_BYTES + (1024 * 1024)

MIDI_RENDERED_AUDIO_MESSAGE = (
    "MIDI event files are not rendered audio. Record the karaoke machine playback "
    "or select WAV, MP3, M4A, AAC, OGG, or FLAC."
)

VALID_ROLES = {"user", "admin"}
SELF_REGISTER_ROLE = "user"
VALID_STATUSES = {"Acceptable", "Needs Improvement", "Problematic"}
EMPIRICAL_RESULT_STATUSES = {
    "good": "Acceptable",
    "good_but_needs_improvement": "Needs Improvement",
    "bad": "Problematic",
}
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
    sr.recommendation_status AS settings_recommendation_status,
    sr.created_at AS settings_created_at,
    sr.applied_at AS settings_applied_at,
    ap.scale_min AS settings_scale_min,
    ap.scale_max AS settings_scale_max,
    ap.scale_step AS settings_scale_step
""".strip()


class AudioAnalyzerExecutionError(RuntimeError):
    def __init__(self, message: str, dump: dict[str, Any]):
        super().__init__(message)
        self.dump = dump


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _clean_profile_image(data: dict[str, Any]) -> tuple[bytes | None, str | None]:
    encoded = data.get("profile_image_base64")
    mime_type = data.get("profile_image_mime")
    if encoded in (None, ""):
        return None, None
    if not isinstance(encoded, str) or not isinstance(mime_type, str):
        raise ValueError("profile image is invalid")
    supported_mime_types = {
        "image/jpeg",
        "image/png",
        "image/webp",
        "image/gif",
        "image/heic",
        "image/heif",
        "image/avif",
        "image/bmp",
    }
    if mime_type not in supported_mime_types:
        raise ValueError("profile image uses an unsupported image format")
    size_limit = f"{MAX_PROFILE_IMAGE_BYTES / (1024 * 1024):g} MB"
    if len(encoded) > ((MAX_PROFILE_IMAGE_BYTES * 4 // 3) + 16):
        raise ValueError(f"profile image must not exceed {size_limit}")
    try:
        image = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError) as error:
        raise ValueError("profile image is invalid") from error
    if not image or len(image) > MAX_PROFILE_IMAGE_BYTES:
        raise ValueError(f"profile image must not exceed {size_limit}")
    iso_brand = image[8:12] if len(image) >= 12 and image[4:8] == b"ftyp" else b""
    signatures = {
        "image/jpeg": image.startswith(b"\xff\xd8\xff"),
        "image/png": image.startswith(b"\x89PNG\r\n\x1a\n"),
        "image/webp": image.startswith(b"RIFF") and image[8:12] == b"WEBP",
        "image/gif": image.startswith((b"GIF87a", b"GIF89a")),
        "image/heic": iso_brand
        in {b"heic", b"heix", b"hevc", b"hevx", b"heim", b"heis", b"mif1", b"msf1"},
        "image/heif": iso_brand in {b"mif1", b"msf1"},
        "image/avif": iso_brand in {b"avif", b"avis"},
        "image/bmp": image.startswith(b"BM"),
    }
    if not signatures[mime_type]:
        raise ValueError("profile image content does not match its file type")
    return image, mime_type


def _clean_birthday(value: Any) -> str:
    if not isinstance(value, str):
        raise ValueError("birthday is required")
    try:
        birthday = datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError as error:
        raise ValueError("birthday must use YYYY-MM-DD") from error
    if birthday >= utcnow().date():
        raise ValueError("birthday must be in the past")
    return birthday.isoformat()


def _clean_phone(value: Any) -> str:
    phone = clean_text(value, "phone_number", 7, 24)
    if not re.fullmatch(r"\+?[0-9 ()-]{7,24}", phone):
        raise ValueError("phone_number is invalid")
    prefix = "+" if phone.startswith("+") else ""
    digits = re.sub(r"\D", "", phone)
    if len(digits) < 7 or len(digits) > 15:
        raise ValueError("phone_number must contain 7-15 digits")
    return f"{prefix}{digits}"


def _profile_response(user: dict[str, Any]) -> dict[str, Any]:
    first_name = user.get("first_name", "")
    last_name = user.get("last_name", "")
    image = user.get("profile_image")
    return {
        "id": user["user_id"],
        "username": user["username"],
        "name": " ".join(part for part in (first_name, last_name) if part),
        "first_name": first_name,
        "last_name": last_name,
        "email": user["email"],
        "address": user.get("address", ""),
        "city": user.get("city", ""),
        "state_province": user.get("state_province", ""),
        "area_code": user.get("area_code", ""),
        "country": user.get("country", ""),
        "country_code": user.get("country_code", ""),
        "phone_number": user.get("phone_number", ""),
        "birthday": str(user.get("birthday") or ""),
        "profile_image_base64": base64.b64encode(bytes(image)).decode("ascii")
        if image
        else None,
        "profile_image_mime": user.get("profile_image_mime"),
        "user_type": user["user_type"],
        "requires_password_change": bool(
            user.get("requires_password_change", False)
        ),
    }


def audio_duration_seconds(path: str) -> int:
    """Return a validated whole-second duration for a readable audio stream."""
    try:
        audio_info = MutagenFile(path)
    except Exception as error:
        raise ValueError("No readable audio stream found") from error
    if audio_info is None or audio_info.info is None:
        raise ValueError("No readable audio stream found")
    duration = int(round(float(audio_info.info.length)))
    if duration < 1 or duration > MAX_AUDIO_SECONDS:
        raise ValueError("Audio duration must be between 1 and 300 seconds")
    return duration


def _analysis_directory(user_id: int, assessment_id: int) -> Path:
    destination = resolve_within_root(
        ANALYSIS_OUTPUT_DIR,
        str(user_id),
        str(assessment_id),
    )
    destination.mkdir(parents=True, exist_ok=True)
    return destination


def cleanup_audio_artifacts(
    user_id: int,
    assessment_id: int,
    temporary_audio_path: str | None = None,
) -> None:
    """Remove a temporary upload and an assessment's analyzer output safely."""
    upload_root = Path(AUDIO_UPLOAD_DIR).resolve()
    if temporary_audio_path:
        upload_path = ensure_within_root(upload_root, temporary_audio_path)
        upload_path.unlink(missing_ok=True)

    analysis_path = resolve_within_root(
        ANALYSIS_OUTPUT_DIR,
        str(user_id),
        str(assessment_id),
    )
    if analysis_path.is_dir():
        shutil.rmtree(analysis_path)


def _remove_temporary_audio(path: str) -> None:
    ensure_within_root(AUDIO_UPLOAD_DIR, path).unlink(missing_ok=True)


def _analysis_artifact_relative_path(path: Path) -> str:
    root = Path(ANALYSIS_OUTPUT_DIR).resolve()
    artifact = ensure_within_root(root, path)
    return artifact.relative_to(root).as_posix()


def _visualization_paths(destination: Path) -> dict[str, str]:
    paths: dict[str, str] = {}
    for kind in ("waveform", "spectrogram"):
        matches = sorted(
            destination.glob(f"*_{kind}.png"),
            key=lambda path: path.stat().st_mtime,
            reverse=True,
        )
        if not matches:
            raise RuntimeError(f"Analyzer did not produce the {kind} visualization")
        paths[kind] = _analysis_artifact_relative_path(matches[0])
    return paths


def _guest_visualization_images(dump: dict[str, Any]) -> dict[str, str]:
    images: dict[str, str] = {}
    visualizations = dump.get("visualizations")
    if not isinstance(visualizations, dict):
        return images
    for kind in ("waveform", "spectrogram"):
        relative_path = visualizations.get(kind)
        if not isinstance(relative_path, str):
            continue
        artifact = ensure_within_root(
            ANALYSIS_OUTPUT_DIR,
            Path(ANALYSIS_OUTPUT_DIR).resolve() / relative_path,
        )
        images[kind] = base64.b64encode(artifact.read_bytes()).decode("ascii")
    return images


def _process_text(value: str | bytes | None, limit: int = 20_000) -> str:
    if value is None:
        return ""
    text = value.decode("utf-8", errors="replace") if isinstance(value, bytes) else value
    return text[-limit:]


def _execute_analyzer_command(
    command: list[str],
    *,
    cwd: str,
    environment: dict[str, str],
    timeout_seconds: int,
) -> subprocess.CompletedProcess[str]:
    process_options: dict[str, Any] = {}
    if os.name == "nt":
        process_options["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        process_options["start_new_session"] = True
    process = subprocess.Popen(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=environment,
        **process_options,
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout_seconds)
    except subprocess.TimeoutExpired as error:
        if os.name == "nt":
            subprocess.run(
                ["taskkill", "/PID", str(process.pid), "/T", "/F"],
                capture_output=True,
                text=True,
                check=False,
            )
        else:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        try:
            stdout, stderr = process.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            stdout, stderr = process.communicate()
        error.output = stdout
        error.stderr = stderr
        raise
    return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)


def _run_audio_analyzer(
    audio_path: str,
    *,
    user_id: int,
    assessment_id: int,
    original_name: str,
    analysis_purpose: str,
) -> dict[str, Any]:
    """Run the standalone analyzer and return its transient structured output."""
    if analysis_purpose not in ALLOWED_ANALYSIS_PURPOSES:
        raise ValueError("analysis_purpose is invalid")
    if not os.path.isfile(AUDIO_ANALYZER_PATH):
        raise RuntimeError("audio_analyzer.py is unavailable")
    if not os.path.isfile(AUDIO_ANALYZER_SETTINGS_PATH):
        raise RuntimeError("audio analyzer settings are unavailable")

    destination = _analysis_directory(user_id, assessment_id)
    command = [
        sys.executable,
        AUDIO_ANALYZER_PATH,
        audio_path,
        "--output-dir",
        str(destination),
        "--settings",
        AUDIO_ANALYZER_SETTINGS_PATH,
        "--no-save-csv",
    ]
    started_at = datetime.now(timezone.utc)
    started_clock = time.monotonic()
    environment = os.environ.copy()
    environment["MPLBACKEND"] = "Agg"
    environment["PYTHONUNBUFFERED"] = "1"
    runtime_cache = Path(ANALYSIS_OUTPUT_DIR).resolve() / "_runtime_cache"
    matplotlib_cache = runtime_cache / "matplotlib"
    numba_cache = runtime_cache / "numba"
    matplotlib_cache.mkdir(parents=True, exist_ok=True)
    numba_cache.mkdir(parents=True, exist_ok=True)
    environment["MPLCONFIGDIR"] = str(matplotlib_cache)
    environment["NUMBA_CACHE_DIR"] = str(numba_cache)

    exit_code: int | None = None
    stdout = ""
    stderr = ""
    process_error: str | None = None
    try:
        completed = _execute_analyzer_command(
            command,
            cwd=os.path.dirname(AUDIO_ANALYZER_PATH),
            environment=environment,
            timeout_seconds=AUDIO_ANALYSIS_TIMEOUT_SECONDS,
        )
        exit_code = completed.returncode
        stdout = _process_text(completed.stdout)
        stderr = _process_text(completed.stderr)
    except subprocess.TimeoutExpired as error:
        stdout = _process_text(error.stdout)
        stderr = _process_text(error.stderr)
        process_error = (
            f"Audio analysis exceeded {AUDIO_ANALYSIS_TIMEOUT_SECONDS} seconds."
        )
    except OSError as error:
        process_error = f"Audio analyzer could not be started: {error}"

    analyzer_output: dict[str, Any] | None = None
    if exit_code in ANALYZER_COMPLETED_EXIT_CODES:
        result_files = sorted(
            destination.glob("*_analysis.json"),
            key=lambda path: path.stat().st_mtime,
            reverse=True,
        )
        if result_files:
            try:
                with result_files[0].open("r", encoding="utf-8") as handle:
                    loaded = json.load(handle)
                if isinstance(loaded, dict):
                    analyzer_output = loaded
            except (OSError, json.JSONDecodeError) as error:
                process_error = f"Analyzer JSON could not be read: {error}"
        else:
            process_error = "Analyzer completed without producing a JSON result."
    elif process_error is None:
        process_error = f"Audio analyzer exited with code {exit_code}."

    empirical_quality: dict[str, Any] | None = None
    if analyzer_output is not None and process_error is None:
        try:
            empirical_quality = _score_analyzer_output(analyzer_output)
        except ValueError as error:
            process_error = f"Empirical quality scoring failed: {error}"

    visualizations: dict[str, str] | None = None
    if analyzer_output is not None and process_error is None:
        try:
            visualizations = _visualization_paths(destination)
        except (OSError, RuntimeError) as error:
            process_error = str(error)

    duration_seconds = round(time.monotonic() - started_clock, 3)
    analysis_completed = (
        analyzer_output is not None
        and empirical_quality is not None
        and process_error is None
    )
    dump: dict[str, Any] = {
        "dump_schema_version": 1,
        "analysis_status": "completed" if analysis_completed else "failed",
        "analysis_purpose": analysis_purpose,
        "upload": {
            "assessment_id": assessment_id,
            "original_file_name": original_name,
        },
        "analyzer_process": {
            "started_at_utc": started_at.isoformat(),
            "duration_seconds": duration_seconds,
            "exit_code": exit_code,
            "quality_thresholds_failed": exit_code == 3,
            "stdout": stdout,
            "stderr": stderr,
        },
        "analysis": analyzer_output,
        "empirical_quality": empirical_quality,
        "visualizations": visualizations,
    }
    if process_error is not None:
        dump["error"] = process_error
    if not analysis_completed:
        raise AudioAnalyzerExecutionError(process_error or "Audio analysis failed", dump)
    return dump


def run_audio_analyzer(
    audio_path: str,
    *,
    user_id: int,
    assessment_id: int,
    original_name: str,
    analysis_purpose: str,
) -> dict[str, Any]:
    """Analyze an upload and retain only its two report visualizations."""
    dump: dict[str, Any] | None = None
    try:
        dump = _run_audio_analyzer(
            audio_path,
            user_id=user_id,
            assessment_id=assessment_id,
            original_name=original_name,
            analysis_purpose=analysis_purpose,
        )
        return dump
    finally:
        root = Path(ANALYSIS_OUTPUT_DIR).resolve()
        destination = (root / str(user_id) / str(assessment_id)).resolve()
        if os.path.commonpath((str(root), str(destination))) != str(root):
            app.logger.error("Refused to clean an invalid analyzer working path")
        elif destination.is_dir():
            visualizations = dump.get("visualizations") if dump else None
            keep = {
                ensure_within_root(root, root / relative_path)
                for relative_path in (
                    visualizations.values()
                    if isinstance(visualizations, dict)
                    else ()
                )
                if isinstance(relative_path, str)
            }
            if not keep:
                shutil.rmtree(destination, ignore_errors=True)
            else:
                for artifact in destination.iterdir():
                    if artifact.is_file() and artifact.resolve() not in keep:
                        artifact.unlink(missing_ok=True)


def _nested_number(data: dict[str, Any], *keys: str) -> float | None:
    value: Any = data
    for key in keys:
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value)


def _empirical_feature_values(analysis: dict[str, Any]) -> dict[str, float | None]:
    """Map analyzer output to the five features used by the 30-file reference."""
    return {
        "loudness": _nested_number(analysis, "loudness", "integrated_lufs"),
        "bass": _nested_number(analysis, "bass", "energy_percentage"),
        "treble": _nested_number(analysis, "treble", "energy_percentage"),
        "sharpness": _nested_number(analysis, "sharpness", "normalized_score"),
        "flatness": _nested_number(analysis, "flatness", "mean"),
    }


def _score_analyzer_output(analysis: dict[str, Any]) -> dict[str, Any]:
    thresholds = load_thresholds()
    empirical = evaluate_features(_empirical_feature_values(analysis), thresholds)
    if empirical.get("overall_score") is None:
        reason = empirical.get("reason", "Empirical audio score is unavailable")
        raise ValueError(str(reason))
    empirical["method"] = "weighted_empirical_good_audio_reference"
    cohort = thresholds.get("cohort")
    empirical["reference_recording_count"] = (
        cohort.get("selected_recording_count") if isinstance(cohort, dict) else None
    )
    empirical["algorithm_version"] = thresholds.get("algorithm_version")
    empirical["quality_profile_version"] = thresholds["quality_profile_version"]
    empirical["quality_profile_checksum"] = thresholds["artifact_checksum"]
    source = thresholds.get("source")
    metrics = thresholds.get("metrics")
    empirical["reference"] = {
        "source_sha256": source.get("sha256") if isinstance(source, dict) else None,
        "classification": thresholds.get("classification"),
        "scoring": thresholds.get("scoring"),
        "overall": thresholds.get("overall"),
        "metrics": metrics,
    }
    return empirical


def _empirical_result_status(empirical: dict[str, Any]) -> str:
    status = empirical.get("overall_status")
    try:
        return EMPIRICAL_RESULT_STATUSES[str(status)]
    except KeyError as error:
        raise ValueError(f"Unsupported empirical quality status: {status!r}") from error


def _enrich_audio_test_row(row: dict[str, Any]) -> dict[str, Any]:
    """Attach reproducible empirical details and backfill legacy null scores."""
    stored_empirical_fields = (
        "empirical_status",
        "worst_feature_status",
        "worst_features",
        "empirical_details",
    )
    if any(row.get(field) is not None for field in stored_empirical_fields):
        raw_details = row.get("empirical_details")
        if isinstance(raw_details, dict):
            empirical = dict(raw_details)
        else:
            try:
                decoded_details = json.loads(raw_details)
            except (TypeError, json.JSONDecodeError):
                decoded_details = {}
            empirical = (
                dict(decoded_details) if isinstance(decoded_details, dict) else {}
            )

        empirical_status = row.get("empirical_status")
        if empirical_status is not None:
            empirical["overall_status"] = str(empirical_status)
        worst_feature_status = row.get("worst_feature_status")
        if worst_feature_status is not None:
            empirical["worst_feature_status"] = str(worst_feature_status)

        raw_worst_features = row.get("worst_features")
        if isinstance(raw_worst_features, list):
            worst_features = raw_worst_features
        else:
            try:
                decoded_worst_features = json.loads(raw_worst_features)
            except (TypeError, json.JSONDecodeError):
                decoded_worst_features = []
            worst_features = (
                decoded_worst_features
                if isinstance(decoded_worst_features, list)
                else []
            )
        empirical["worst_features"] = worst_features

        empirical_score = _nested_number(empirical, "overall_score")
        if empirical_score is None:
            stored_score = row.get("score")
            if (
                not isinstance(stored_score, bool)
                and isinstance(stored_score, (int, float))
                and math.isfinite(float(stored_score))
            ):
                empirical_score = float(stored_score)
                empirical["overall_score"] = empirical_score
        row["empirical_quality"] = empirical
        if row.get("score") is None and empirical_score is not None:
            row["score"] = empirical_score
        if empirical_status is not None:
            row["status"] = _empirical_result_status(empirical)
        return row

    values = {
        key: row.get(key)
        for key in ("loudness", "bass", "treble", "sharpness", "flatness")
    }
    empirical = evaluate_features(values)
    row["empirical_quality"] = empirical
    empirical_score = _nested_number(empirical, "overall_score")
    if row.get("score") is None and empirical_score is not None:
        row["score"] = empirical_score
    if empirical_score is not None:
        row["status"] = _empirical_result_status(empirical)
    return row


def _attach_stored_recommendation(row: dict[str, Any]) -> dict[str, Any]:
    recommendation = settings_recommendation_service.stored_recommendation_payload(
        row
    )
    for key in tuple(row):
        if key.startswith("settings_"):
            row.pop(key)
    if row.get("analysis_purpose") == "settings_suggestion":
        row["settings_recommendation"] = recommendation
    return row


def _analysis_safety_signals(analysis: dict[str, Any]) -> dict[str, Any]:
    quality = analysis.get("quality_assessment")
    quality = quality if isinstance(quality, dict) else {}
    measured = quality.get("measured")
    measured = measured if isinstance(measured, dict) else {}
    thresholds = quality.get("thresholds")
    thresholds = thresholds if isinstance(thresholds, dict) else {}

    clipped = _nested_number(analysis, "distortion", "clipped_sample_percentage")
    clipping_limit = _nested_number(
        thresholds,
        "clipped_samples_failure_above_percentage",
    )
    distortion = _nested_number(analysis, "distortion", "estimated_score")
    distortion_limit = _nested_number(thresholds, "distortion_warning_above")
    snr = _nested_number(measured, "estimated_snr_db")
    noise_limit = _nested_number(thresholds, "snr_warning_below_db")
    return {
        "silent": False,
        "corrupt": False,
        "too_short": False,
        "clipping": (
            clipped is not None
            and clipping_limit is not None
            and clipped > clipping_limit
        ),
        "excessive_noise": (
            snr is not None and noise_limit is not None and snr < noise_limit
        ),
        "excessive_distortion": (
            distortion is not None
            and distortion_limit is not None
            and distortion > distortion_limit
        ),
        "low_confidence_metrics": [],
    }


def summarize_audio_analysis(dump: dict[str, Any]) -> dict[str, Any]:
    """Convert transient analyzer output into the public measured result."""
    analysis = dump.get("analysis")
    if not isinstance(analysis, dict):
        raise RuntimeError("Analyzer output is missing")
    empirical = dump.get("empirical_quality")
    if not isinstance(empirical, dict):
        empirical = _score_analyzer_output(analysis)
        dump["empirical_quality"] = empirical
    quality_score = _nested_number(empirical, "overall_score")
    if quality_score is None:
        raise RuntimeError("Empirical audio score is unavailable")
    result_status = _empirical_result_status(empirical)
    noise_level = _nested_number(analysis, "noise", "noise_dbfs")
    distortion_level = _nested_number(analysis, "distortion", "estimated_score")
    bass = _nested_number(analysis, "bass", "energy_percentage")
    treble = _nested_number(analysis, "treble", "energy_percentage")
    loudness = _nested_number(analysis, "loudness", "integrated_lufs")
    if loudness is None:
        loudness = _nested_number(analysis, "loudness", "mean_dbfs")
    sharpness = _nested_number(analysis, "sharpness", "normalized_score")
    flatness = _nested_number(analysis, "flatness", "mean")
    return {
        "score": quality_score,
        "status": result_status,
        "noise_level": noise_level,
        "distortion_level": distortion_level,
        "bass": bass,
        "treble": treble,
        "loudness": loudness,
        "sharpness": sharpness,
        "flatness": flatness,
        "empirical_quality": empirical,
        "safety_signals": _analysis_safety_signals(analysis),
    }


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
    cursor = conn.cursor()
    recommendation_id = None
    recommendation_response = None
    try:
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
            if context.verification:
                cursor.execute(
                    """SELECT sr.recommendation_id
                       FROM settings_recommendation sr
                       LEFT JOIN settings_recommendation child
                         ON child.parent_recommendation_id = sr.recommendation_id
                       WHERE sr.recommendation_id = %s AND sr.user_id = %s
                         AND sr.amplifier_profile_id = %s
                         AND sr.genre_profile_version = %s
                         AND sr.genre_profile_checksum = %s
                         AND sr.recommendation_status = 'applied'
                         AND child.recommendation_id IS NULL
                       FOR UPDATE""",
                    (
                        context.verification_of,
                        context.user_id,
                        context.amplifier_profile_id,
                        recommendation.profile_version,
                        recommendation.profile_checksum,
                    ),
                )
                if cursor.fetchone() is None:
                    raise ValueError(
                        "verification_of is no longer eligible for verification "
                        "with this profile version and checksum"
                    )

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
                    genre_profile_version, genre_profile_checksum,
                    recommendation_status)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                           %s, %s, %s, %s, %s)""",
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
                    recommendation.profile_version,
                    recommendation.profile_checksum,
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


def send_registration_otp(email: str, code: str) -> None:
    if not all((SMTP_HOST, SMTP_USERNAME, SMTP_PASSWORD, SMTP_FROM)):
        raise RuntimeError("SMTP is not configured; set SMTP_HOST, SMTP_USERNAME, SMTP_PASSWORD, and SMTP_FROM")
    message = EmailMessage()
    message["Subject"] = "Email Verification OTP — Audio Evaluation System"
    message["From"] = SMTP_FROM
    message["To"] = email
    message.set_content(
        f"""Dear User,

Thank you for registering with our application.

Your One-Time Password (OTP) for email verification is:

**{code}**

This verification code is valid for **{OTP_MINUTES} minutes**. Please enter this code in the application to complete your registration.

For your security, do not share this OTP with anyone. Our team will never ask you for your verification code.

If you did not request this verification or believe you received this email in error, please disregard this message. No further action is required, and your account will not be activated unless the correct OTP is entered.

Thank you,

**The Audio Evaluation System Team**
"""
    )
    with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=15) as server:
        server.starttls()
        server.login(SMTP_USERNAME, SMTP_PASSWORD)
        server.send_message(message)


def send_temporary_password_email(email: str, temporary_password: str) -> None:
    if not all((SMTP_HOST, SMTP_USERNAME, SMTP_PASSWORD, SMTP_FROM)):
        raise RuntimeError("SMTP is not configured")
    message = EmailMessage()
    message["Subject"] = "Your temporary KaraOK password"
    message["From"] = SMTP_FROM
    message["To"] = email
    message.set_content(
        f"""A password reset was requested for your KaraOK account.

Use this temporary password to sign in to the KaraOK application:

{temporary_password}

You will be required to choose a new password immediately after signing in. Do
not share this temporary password. If you did not request this reset, contact
the KaraOK administrator.
"""
    )
    with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=15) as server:
        server.starttls()
        server.login(SMTP_USERNAME, SMTP_PASSWORD)
        server.send_message(message)


def client_ip() -> str:
    return (request.remote_addr or "")[:45]


@app.before_request
def begin_api_request_log() -> None:
    if (
        not app.config.get("TESTING", False)
        and request.path.startswith("/api/")
        and request.method != "OPTIONS"
    ):
        g.api_request_started = time.monotonic()


@app.after_request
def complete_api_request_log(response):
    started = getattr(g, "api_request_started", None)
    if started is None:
        return response
    duration_ms = round((time.monotonic() - started) * 1000.0, 3)
    conn = None
    cursor = None
    try:
        conn = get_db()
        cursor = conn.cursor()
        cursor.execute(
            """INSERT INTO api_request_log
               (user_id, method, path, endpoint, status_code, duration_ms,
                ip_address, user_agent)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
            (
                getattr(g, "authenticated_user_id", None),
                request.method[:10],
                request.path[:255],
                (request.endpoint or "").rsplit(".", 1)[-1][:100] or None,
                response.status_code,
                duration_ms,
                client_ip(),
                request.headers.get("User-Agent", "")[:255],
            ),
        )
        conn.commit()
    except Exception:
        app.logger.exception("Could not write API request log")
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None and conn.is_connected():
            conn.close()
    return response


def audit(
    action: str,
    result: str,
    *,
    user_id: int | None = None,
    resource_type: str | None = None,
    resource_id: int | None = None,
    details: str | None = None,
) -> None:
    try:
        conn = get_db()
        cursor = conn.cursor()
        cursor.execute(
            """INSERT INTO audit_log
               (user_id, action, resource_type, resource_id, result, ip_address, user_agent, details)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
            (
                user_id,
                action[:80],
                resource_type,
                resource_id,
                result,
                client_ip(),
                request.headers.get("User-Agent", "")[:255],
                details[:500] if details else None,
            ),
        )
        conn.commit()
        cursor.close()
        conn.close()
    except Error:
        app.logger.exception("Could not write audit log")


def issue_access_token(user: dict[str, Any]) -> tuple[str, int]:
    return create_access_token(
        user,
        secret=JWT_SECRET,
        issuer=JWT_ISSUER,
        lifetime_minutes=ACCESS_TOKEN_MINUTES,
    )


def create_refresh_token(user_id: int) -> tuple[str, datetime]:
    raw_token = secrets.token_urlsafe(48)
    expires = utcnow() + timedelta(days=REFRESH_TOKEN_DAYS)
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        """INSERT INTO refresh_token
           (user_id, token_hash, expires_at, ip_address, user_agent)
           VALUES (%s, %s, %s, %s, %s)""",
        (user_id, token_hash(raw_token), expires.replace(tzinfo=None), client_ip(), request.headers.get("User-Agent", "")[:255]),
    )
    conn.commit()
    cursor.close()
    conn.close()
    return raw_token, expires


def auth_response(user: dict[str, Any], status: int = 200):
    access_token, access_expires_at = issue_access_token(user)
    refresh_token, refresh_expires_at = create_refresh_token(user["user_id"])
    g.authenticated_user_id = int(user["user_id"])
    return jsonify(
        {
            "user": _profile_response(user),
            "access_token": access_token,
            "access_expires_at": access_expires_at,
            "refresh_token": refresh_token,
            "refresh_expires_at": int(refresh_expires_at.timestamp()),
        }
    ), status


def _token_precedes_security_update(
    payload: dict[str, Any],
    account: dict[str, Any],
) -> bool:
    return token_precedes_security_update(payload, account)


def require_auth(*roles: str) -> Callable:
    def decorator(view: Callable) -> Callable:
        @wraps(view)
        def wrapped(*args, **kwargs):
            header = request.headers.get("Authorization", "")
            if not header.startswith("Bearer ") or not JWT_SECRET:
                reason = (
                    "Missing bearer token"
                    if not header.startswith("Bearer ")
                    else "JWT secret is not configured"
                )
                app.logger.warning("Access token rejected: %s", reason)
                audit("access_denied", "failure", details=reason)
                return jsonify({"error": "Authentication required"}), 401
            try:
                payload = jwt.decode(
                    header[7:],
                    JWT_SECRET,
                    algorithms=["HS256"],
                    issuer=JWT_ISSUER,
                    options={"require": ["sub", "role", "exp", "iat", "jti"]},
                )
                g.user_id = int(payload["sub"])
                g.user_role = payload["role"]
                conn = get_db()
                cursor = conn.cursor(dictionary=True)
                cursor.execute("SELECT 1 FROM revoked_access_token WHERE jti = %s", (payload["jti"],))
                revoked = cursor.fetchone() is not None
                cursor.execute(
                    """SELECT role, is_active, email_verified_at,
                              UNIX_TIMESTAMP(security_updated_at)
                                  AS security_updated_at_epoch,
                              requires_password_change
                       FROM user WHERE user_id = %s""",
                    (g.user_id,),
                )
                account = cursor.fetchone()
                cursor.close()
                conn.close()
                if revoked:
                    raise jwt.InvalidTokenError("Access token was revoked")
                if (
                    not account
                    or not account["is_active"]
                    or account["email_verified_at"] is None
                    or account["role"] != g.user_role
                    or _token_precedes_security_update(payload, account)
                ):
                    raise jwt.InvalidTokenError("Account security state changed")
            except (jwt.PyJWTError, TypeError, ValueError) as error:
                reason = str(error).strip() or type(error).__name__
                app.logger.warning("Access token rejected: %s", reason)
                audit(
                    "access_denied",
                    "failure",
                    details=f"Invalid or expired access token: {reason}",
                )
                return jsonify({"error": "Invalid or expired access token"}), 401
            g.authenticated_user_id = g.user_id
            if roles and g.user_role not in roles:
                audit("access_denied", "failure", user_id=g.user_id, details="Insufficient role")
                return jsonify({"error": "Forbidden"}), 403
            g.requires_password_change = bool(account["requires_password_change"])
            if g.requires_password_change and not (
                request.endpoint or ""
            ).endswith("change_password"):
                audit(
                    "access_denied",
                    "failure",
                    user_id=g.user_id,
                    details="Password change required",
                )
                return jsonify({"error": "Password change required"}), 403
            return view(*args, **kwargs)

        return wrapped

    return decorator


@app.errorhandler(ValueError)
def handle_validation_error(error: ValueError):
    audit("input_validation_failed", "failure", user_id=getattr(g, "user_id", None), details=str(error))
    return jsonify({"error": str(error)}), 400


@app.errorhandler(Error)
def handle_database_error(error: Error):
    app.logger.exception("Database error")
    return jsonify({"error": "Database operation failed"}), 500


@app.errorhandler(HTTPException)
def handle_http_error(error: HTTPException):
    status_code = error.code or 500
    if status_code == 429:
        message = "Too many requests. Please wait before trying again."
    elif status_code >= 500:
        message = "Internal server error"
    else:
        message = error.description or error.name
    return jsonify({"error": message}), status_code


@app.errorhandler(Exception)
def handle_unexpected_error(error: Exception):
    app.logger.exception("Unhandled application error")
    return jsonify({"error": "Internal server error"}), 500


@app.after_request
def security_headers(response):
    return apply_security_headers(response)


def health():
    try:
        conn = get_db()
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        cursor.fetchone()
        cursor.close()
        conn.close()
        return jsonify({"status": "ok", "db": "connected"})
    except Error:
        return jsonify({"status": "error", "db": "unavailable"}), 503


@limiter.limit("5 per hour")
def register():
    data = json_body()
    username = clean_text(data.get("username"), "username", 3, 50)
    if not re.fullmatch(r"[A-Za-z0-9_.-]{3,50}", username):
        raise ValueError(
            "username may contain only letters, numbers, dots, dashes, and underscores"
        )
    first_name = clean_text(data.get("first_name"), "first_name", 1, 80)
    last_name = clean_text(data.get("last_name"), "last_name", 1, 80)
    email = clean_email(data.get("email"))
    password = validate_password(data.get("password"))
    address = clean_text(data.get("address"), "address", 5, 255)
    city = clean_text(data.get("city"), "city", 2, 100)
    state_province = clean_text(
        data.get("state_province"), "state_province", 2, 100
    )
    area_code = clean_text(data.get("area_code"), "area_code", 2, 20)
    country = clean_text(data.get("country"), "country", 2, 80)
    country_code = clean_text(
        data.get("country_code"), "country_code", 2, 2
    ).upper()
    if not re.fullmatch(r"[A-Z]{2}", country_code):
        raise ValueError("country_code must be a two-letter ISO country code")
    phone_number = _clean_phone(data.get("phone_number"))
    birthday = _clean_birthday(data.get("birthday"))
    profile_image, profile_image_mime = _clean_profile_image(data)
    if "user_type" in data and data.get("user_type") != SELF_REGISTER_ROLE:
        raise ValueError("public registration creates user accounts only")

    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            """SELECT user_id, username, email, email_verified_at
               FROM user WHERE email = %s LIMIT 1 FOR UPDATE""",
            (email,),
        )
        email_user = cursor.fetchone()
        cursor.execute(
            """SELECT user_id, username, email, email_verified_at
               FROM user WHERE username = %s LIMIT 1 FOR UPDATE""",
            (username,),
        )
        username_user = cursor.fetchone()

        if email_user and (
            email_user["email_verified_at"] is not None
            or email_user["username"] != username
        ):
            return jsonify({"error": "Unable to create account"}), 409
        if username_user and (
            not email_user or username_user["user_id"] != email_user["user_id"]
        ):
            return jsonify({"error": "Unable to create account"}), 409

        password_hash = password_hasher.hash(password)
        if email_user:
            user_id = email_user["user_id"]
            cursor.execute(
                """UPDATE user
                   SET username = %s, first_name = %s, last_name = %s,
                       password = %s, address = %s, city = %s,
                       state_province = %s, area_code = %s, country = %s,
                       country_code = %s,
                       phone_number = %s, birthday = %s,
                       profile_image = %s, profile_image_mime = %s,
                       role = 'user'
                   WHERE user_id = %s AND email_verified_at IS NULL""",
                (
                    username,
                    first_name,
                    last_name,
                    password_hash,
                    address,
                    city,
                    state_province,
                    area_code,
                    country,
                    country_code,
                    phone_number,
                    birthday,
                    profile_image,
                    profile_image_mime,
                    user_id,
                ),
            )
        else:
            cursor.execute(
                """INSERT INTO user
                   (username, first_name, last_name, email, password, address,
                    city, state_province, area_code, country, country_code,
                    phone_number, birthday, profile_image, profile_image_mime,
                    role, email_verified_at)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                           %s, %s, %s, %s, 'user', NULL)""",
                (
                    username,
                    first_name,
                    last_name,
                    email,
                    password_hash,
                    address,
                    city,
                    state_province,
                    area_code,
                    country,
                    country_code,
                    phone_number,
                    birthday,
                    profile_image,
                    profile_image_mime,
                ),
            )
            user_id = cursor.lastrowid

        code = f"{secrets.randbelow(1_000_000):06d}"
        cursor.execute(
            "DELETE FROM registration_otp WHERE user_id = %s",
            (user_id,),
        )
        cursor.execute(
            """INSERT INTO registration_otp
               (user_id, code_hash, expires_at)
               VALUES (%s, %s, UTC_TIMESTAMP() + INTERVAL %s MINUTE)""",
            (user_id, token_hash(code), OTP_MINUTES),
        )
        if SMTP_HOST and SMTP_USERNAME and SMTP_PASSWORD and SMTP_FROM:
            send_registration_otp(email, code)
        elif not (DEV_MODE and EXPOSE_REGISTRATION_OTP):
            raise RuntimeError("SMTP is not configured")
        conn.commit()
    except IntegrityError:
        conn.rollback()
        return jsonify({"error": "Unable to create account"}), 409
    except (OSError, smtplib.SMTPException, RuntimeError):
        conn.rollback()
        app.logger.exception("Registration OTP delivery failed")
        return jsonify({"error": "Unable to send verification email"}), 503
    finally:
        cursor.close()
        conn.close()
    response = {
        "message": "Verification code sent to the supplied email",
        "email": email,
    }
    if DEV_MODE and EXPOSE_REGISTRATION_OTP:
        response["development_code"] = code
    g.authenticated_user_id = int(user_id)
    return jsonify(response), 202


@limiter.limit("10 per hour")
def verify_registration():
    data = json_body()
    email = clean_email(data.get("email"))
    code = data.get("code")
    if not isinstance(code, str) or not re.fullmatch(r"\d{6}", code):
        raise ValueError("verification code must be six digits")
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        """SELECT registration_otp.registration_id,
                  registration_otp.code_hash,
                  registration_otp.attempts,
                  user.user_id, user.username, user.first_name, user.last_name,
                  user.email, user.address, user.city, user.state_province,
                  user.area_code, user.country, user.country_code,
                  user.phone_number, user.birthday, user.profile_image,
                  user.profile_image_mime, user.role
           FROM registration_otp
           JOIN user ON user.user_id = registration_otp.user_id
           WHERE user.email = %s AND user.email_verified_at IS NULL
             AND registration_otp.expires_at > UTC_TIMESTAMP()
             AND registration_otp.attempts < 5
           FOR UPDATE""",
        (email,),
    )
    pending = cursor.fetchone()
    if not pending or not secrets.compare_digest(pending["code_hash"], token_hash(code)):
        if pending:
            cursor.execute(
                "UPDATE registration_otp SET attempts = attempts + 1 WHERE registration_id = %s",
                (pending["registration_id"],),
            )
            conn.commit()
        cursor.close()
        conn.close()
        return jsonify({"error": "Invalid or expired verification code"}), 400
    try:
        cursor.execute(
            """UPDATE user SET email_verified_at = UTC_TIMESTAMP()
               WHERE user_id = %s AND email_verified_at IS NULL""",
            (pending["user_id"],),
        )
        cursor.execute(
            "DELETE FROM registration_otp WHERE registration_id = %s",
            (pending["registration_id"],),
        )
        conn.commit()
    except IntegrityError:
        conn.rollback()
        cursor.close()
        conn.close()
        return jsonify({"error": "Unable to create account"}), 409
    cursor.close()
    conn.close()
    user = {
        "user_id": pending["user_id"],
        "username": pending["username"],
        "first_name": pending["first_name"],
        "last_name": pending["last_name"],
        "email": pending["email"],
        "address": pending["address"],
        "city": pending["city"],
        "state_province": pending["state_province"],
        "area_code": pending["area_code"],
        "country": pending["country"],
        "country_code": pending["country_code"],
        "phone_number": pending["phone_number"],
        "birthday": pending["birthday"],
        "profile_image": pending["profile_image"],
        "profile_image_mime": pending["profile_image_mime"],
        "user_type": pending["role"],
    }
    audit(
        "registration",
        "success",
        user_id=pending["user_id"],
        resource_type="user",
        resource_id=pending["user_id"],
    )
    return auth_response(user, 201)


@limiter.limit("5 per minute")
def login():
    data = json_body()
    identifier = clean_text(
        data.get("identifier", data.get("email")), "username or email", 3, 254
    )
    is_email = EMAIL_RE.fullmatch(identifier) is not None
    if is_email:
        identifier = clean_email(identifier)
    elif not re.fullmatch(r"[A-Za-z0-9_.-]{3,50}", identifier):
        raise ValueError("username is invalid")
    password = data.get("password")
    if not isinstance(password, str) or len(password) > 128:
        raise ValueError("password is invalid")

    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        f"""SELECT u.user_id, u.username, u.first_name, u.last_name, u.email,
                   u.address, u.city, u.state_province, u.area_code,
                   u.country, u.country_code, u.phone_number,
                   u.birthday, u.profile_image, u.profile_image_mime,
                   u.role AS user_type,
                   u.password AS password_hash, u.is_active, u.email_verified_at,
                   u.requires_password_change
            FROM user u
            WHERE u.{"email" if is_email else "username"} = %s LIMIT 1""",
        (identifier,),
    )
    user = cursor.fetchone()
    cursor.close()
    conn.close()

    valid = False
    if user and user["is_active"] and user["email_verified_at"] is not None:
        try:
            valid = password_hasher.verify(user["password_hash"], password)
        except (VerifyMismatchError, InvalidHashError):
            valid = False
    if not valid:
        audit("login", "failure", user_id=user["user_id"] if user else None)
        return jsonify({"error": "Invalid username/email or password"}), 401
    if password_hasher.check_needs_rehash(user["password_hash"]):
        conn = get_db()
        cursor = conn.cursor()
        cursor.execute("UPDATE user SET password = %s WHERE user_id = %s", (password_hasher.hash(password), user["user_id"]))
        conn.commit()
        cursor.close()
        conn.close()
    audit("login", "success", user_id=user["user_id"])
    return auth_response(user)


@limiter.limit("20 per hour")
def refresh():
    raw_token = json_body().get("refresh_token")
    if not isinstance(raw_token, str) or len(raw_token) > 200:
        return jsonify({"error": "Invalid refresh token"}), 401
    hashed = token_hash(raw_token)
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        """SELECT rt.refresh_token_id AS token_id, rt.user_id, rt.expires_at, rt.revoked_at,
                  u.username, u.first_name, u.last_name, u.email, u.address,
                  u.city, u.state_province, u.area_code, u.country,
                  u.country_code, u.phone_number, u.birthday, u.profile_image,
                  u.profile_image_mime, u.role AS user_type, u.is_active,
                  u.email_verified_at,
                  u.requires_password_change
           FROM refresh_token rt JOIN user u ON u.user_id = rt.user_id
           WHERE rt.token_hash = %s FOR UPDATE""",
        (hashed,),
    )
    row = cursor.fetchone()
    if (
        not row
        or row["revoked_at"]
        or row["expires_at"] <= datetime.utcnow()
        or not row["is_active"]
        or row["email_verified_at"] is None
    ):
        cursor.close()
        conn.close()
        audit("token_refresh", "failure")
        return jsonify({"error": "Invalid or expired refresh token"}), 401
    cursor.execute("UPDATE refresh_token SET revoked_at = UTC_TIMESTAMP() WHERE refresh_token_id = %s", (row["token_id"],))
    conn.commit()
    cursor.close()
    conn.close()
    audit("token_refresh", "success", user_id=row["user_id"])
    return auth_response(row)


def logout():
    raw_token = json_body().get("refresh_token")
    header = request.headers.get("Authorization", "")
    access_payload = None
    if header.startswith("Bearer ") and JWT_SECRET:
        try:
            access_payload = jwt.decode(
                header[7:],
                JWT_SECRET,
                algorithms=["HS256"],
                issuer=JWT_ISSUER,
                options={"verify_exp": False, "require": ["sub", "exp", "jti"]},
            )
        except jwt.PyJWTError:
            access_payload = None
    if access_payload:
        g.authenticated_user_id = int(access_payload["sub"])
    if isinstance(raw_token, str):
        conn = get_db()
        cursor = conn.cursor()
        cursor.execute(
            "UPDATE refresh_token SET revoked_at = UTC_TIMESTAMP() WHERE token_hash = %s AND revoked_at IS NULL",
            (token_hash(raw_token),),
        )
        if access_payload:
            cursor.execute(
                """INSERT IGNORE INTO revoked_access_token (jti, user_id, expires_at)
                   VALUES (%s, %s, FROM_UNIXTIME(%s))""",
                (access_payload["jti"], int(access_payload["sub"]), int(access_payload["exp"])),
            )
        conn.commit()
        cursor.close()
        conn.close()
        audit("logout", "success", user_id=int(access_payload["sub"]) if access_payload else None)
    return jsonify({"message": "Logged out"})


@limiter.limit("3 per hour", exempt_when=lambda: DEV_MODE)
def forgot_password():
    email = clean_email(json_body().get("email"))
    audit_result = "success"
    audit_details = "Password reset request accepted"
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        """SELECT user_id AS id FROM user
           WHERE email = %s AND is_active = TRUE
             AND email_verified_at IS NOT NULL""",
        (email,),
    )
    user = cursor.fetchone()
    if user:
        temporary_password = generate_temporary_password()
        try:
            cursor.execute(
                """UPDATE user
                   SET password = %s, requires_password_change = TRUE
                   WHERE user_id = %s""",
                (password_hasher.hash(temporary_password), user["id"]),
            )
            cursor.execute(
                """UPDATE refresh_token SET revoked_at = UTC_TIMESTAMP()
                   WHERE user_id = %s AND revoked_at IS NULL""",
                (user["id"],),
            )
            if SMTP_HOST and SMTP_USERNAME and SMTP_PASSWORD and SMTP_FROM:
                send_temporary_password_email(email, temporary_password)
            else:
                raise RuntimeError("SMTP is not configured")
            conn.commit()
        except (smtplib.SMTPException, OSError, RuntimeError):
            conn.rollback()
            audit_result = "failure"
            audit_details = "Password reset email delivery failed"
            app.logger.exception("Password reset email delivery failed")
    cursor.close()
    conn.close()
    audit(
        "password_reset_requested",
        audit_result,
        user_id=user["id"] if user else None,
        details=audit_details,
    )
    return jsonify({"message": "If the account exists, a temporary password has been sent."})


@limiter.limit("10 per hour", exempt_when=lambda: DEV_MODE)
@require_auth("user", "admin")
def change_password():
    data = json_body()
    current_password = data.get("current_password")
    new_password = validate_password(data.get("new_password"))
    if not g.requires_password_change and (
        not isinstance(current_password, str) or len(current_password) > 128
    ):
        raise ValueError("current password is invalid")
    if isinstance(current_password, str) and secrets.compare_digest(current_password, new_password):
        raise ValueError("new password must be different from the current password")

    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT password FROM user WHERE user_id = %s AND is_active = TRUE", (g.user_id,))
    user = cursor.fetchone()
    if not user:
        cursor.close()
        conn.close()
        return jsonify({"error": "Account is unavailable"}), 401
    if g.requires_password_change:
        try:
            if password_hasher.verify(user["password"], new_password):
                raise ValueError("new password must be different from the temporary password")
        except (VerifyMismatchError, InvalidHashError):
            pass
    else:
        try:
            valid = password_hasher.verify(user["password"], current_password)
        except (VerifyMismatchError, InvalidHashError):
            valid = False
        if not valid:
            cursor.close()
            conn.close()
            return jsonify({"error": "Current password is incorrect"}), 401

    cursor.execute(
        """UPDATE user
           SET password = %s, requires_password_change = FALSE
           WHERE user_id = %s""",
        (password_hasher.hash(new_password), g.user_id),
    )
    cursor.execute(
        "UPDATE refresh_token SET revoked_at = UTC_TIMESTAMP() WHERE user_id = %s AND revoked_at IS NULL",
        (g.user_id,),
    )
    conn.commit()
    cursor.close()
    conn.close()
    audit("password_changed", "success", user_id=g.user_id, resource_type="user", resource_id=g.user_id)
    return jsonify({"message": "Password changed successfully. Please log in again."})


@require_auth("admin")
def get_users():
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        """SELECT user_id AS id, username,
                  CONCAT(first_name, ' ', last_name) AS name,
                  first_name, last_name, email, address, city,
                  state_province, area_code, country, country_code,
                  phone_number, birthday,
                  role AS user_type, is_active, email_verified_at, created_at
           FROM user ORDER BY created_at DESC"""
    )
    rows = cursor.fetchall()
    cursor.close()
    conn.close()
    return jsonify(rows)


@require_auth("user")
def update_profile():
    data = json_body()
    allowed_fields = {
        "username",
        "first_name",
        "last_name",
        "address",
        "city",
        "state_province",
        "area_code",
        "country",
        "country_code",
        "phone_number",
        "birthday",
        "profile_image_base64",
        "profile_image_mime",
    }
    immutable_fields = {"email"}.intersection(data)
    if immutable_fields:
        raise ValueError("email cannot be changed")
    unexpected_fields = set(data).difference(allowed_fields)
    if unexpected_fields:
        raise ValueError("profile contains unsupported fields")

    username = clean_text(data.get("username"), "username", 3, 50)
    if not re.fullmatch(r"[A-Za-z0-9_.-]{3,50}", username):
        raise ValueError(
            "username may contain only letters, numbers, dots, dashes, and underscores"
        )
    first_name = clean_text(data.get("first_name"), "first_name", 1, 80)
    last_name = clean_text(data.get("last_name"), "last_name", 1, 80)
    address = clean_text(data.get("address"), "address", 5, 255)
    city = clean_text(data.get("city"), "city", 2, 100)
    state_province = clean_text(
        data.get("state_province"), "state_province", 2, 100
    )
    area_code = clean_text(data.get("area_code"), "area_code", 2, 20)
    country = clean_text(data.get("country"), "country", 2, 80)
    country_code = clean_text(
        data.get("country_code"), "country_code", 2, 2
    ).upper()
    if not re.fullmatch(r"[A-Z]{2}", country_code):
        raise ValueError("country_code must be a two-letter ISO country code")
    phone_number = _clean_phone(data.get("phone_number"))
    birthday = _clean_birthday(data.get("birthday"))
    image_supplied = "profile_image_base64" in data
    profile_image = profile_image_mime = None
    if image_supplied:
        profile_image, profile_image_mime = _clean_profile_image(data)

    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            """SELECT username, phone_number FROM user
               WHERE user_id <> %s AND (username = %s OR phone_number = %s)
               LIMIT 1""",
            (g.user_id, username, phone_number),
        )
        conflict = cursor.fetchone()
        if conflict:
            return jsonify({"error": "Username or phone number is already in use"}), 409

        profile_columns = ""
        parameters: list[Any] = [
            username,
            first_name,
            last_name,
            address,
            city,
            state_province,
            area_code,
            country,
            country_code,
            phone_number,
            birthday,
        ]
        if image_supplied:
            profile_columns = ", profile_image = %s, profile_image_mime = %s"
            parameters.extend((profile_image, profile_image_mime))
        parameters.append(g.user_id)
        cursor.execute(
            f"""UPDATE user
                SET username = %s, first_name = %s, last_name = %s,
                    address = %s, city = %s, state_province = %s,
                    area_code = %s, country = %s, country_code = %s,
                    phone_number = %s, birthday = %s{profile_columns}
                WHERE user_id = %s AND is_active = TRUE""",
            tuple(parameters),
        )
        if cursor.rowcount != 1:
            conn.rollback()
            return jsonify({"error": "Account is unavailable"}), 404
        cursor.execute(
            """SELECT user_id, username, first_name, last_name, email,
                      address, city, state_province, area_code, country,
                      country_code, phone_number, birthday, profile_image,
                      profile_image_mime, role AS user_type,
                      requires_password_change
               FROM user WHERE user_id = %s""",
            (g.user_id,),
        )
        updated_user = cursor.fetchone()
        conn.commit()
    except IntegrityError:
        conn.rollback()
        return jsonify({"error": "Username or phone number is already in use"}), 409
    finally:
        cursor.close()
        conn.close()

    audit(
        "profile_updated",
        "success",
        user_id=g.user_id,
        resource_type="user",
        resource_id=g.user_id,
    )
    return jsonify({"user": _profile_response(updated_user)}), 200


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
                  r.empirical_details, r.quality_profile_version,
                  r.quality_profile_checksum, a.result_status AS status,
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
                  r.empirical_details, r.quality_profile_version,
                  r.quality_profile_checksum, a.result_status AS status,
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
    except Exception:
        os.remove(stored_path)
        return jsonify({"error": "Audio file is corrupted or unreadable"}), 422

    conn = get_db()
    cursor = conn.cursor()
    try:
        cursor.execute(
            """INSERT INTO assessment
               (user_id, assessment_status, test_name,
                duration_seconds, result_status, analysis_purpose)
               VALUES (%s, 'Processing', %s, %s, 'Acceptable', %s)""",
            (
                g.user_id,
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


@require_auth("user")
def get_audio_visualization(test_id: int, kind: str):
    if kind not in {"waveform", "spectrogram"}:
        return jsonify({"error": "Visualization not found"}), 404
    column = f"{kind}_path"
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        f"""SELECT r.{column} AS artifact_path
            FROM assessment a
            JOIN audio_analysis_result r
              ON r.assessment_id = a.assessment_id
            WHERE a.assessment_id = %s AND a.user_id = %s""",
        (test_id, g.user_id),
    )
    record = cursor.fetchone()
    cursor.close()
    conn.close()
    relative_path = record.get("artifact_path") if record else None
    if not isinstance(relative_path, str):
        return jsonify({"error": "Visualization not found"}), 404
    try:
        artifact = ensure_within_root(
            ANALYSIS_OUTPUT_DIR,
            Path(ANALYSIS_OUTPUT_DIR).resolve() / relative_path,
        )
    except RuntimeError:
        app.logger.error("Refused to serve an invalid visualization path")
        return jsonify({"error": "Visualization not found"}), 404
    if not artifact.is_file():
        return jsonify({"error": "Visualization not found"}), 404
    return send_file(
        artifact,
        mimetype="image/png",
        conditional=True,
        max_age=3600,
    )


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
    if upload_record["quality_score"] is None:
        return jsonify({"error": "Analysis output not found"}), 404

    def decoded_json(value: Any, fallback: Any) -> Any:
        if value is None:
            return fallback
        if isinstance(value, (dict, list)):
            return value
        try:
            return json.loads(value)
        except (TypeError, json.JSONDecodeError):
            return fallback

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
                "status": upload_record["result_status"],
                "empirical_status": upload_record["empirical_status"],
                "worst_feature_status": upload_record["worst_feature_status"],
                "worst_features": decoded_json(
                    upload_record["worst_features"], []
                ),
            },
        },
        "empirical_quality": decoded_json(
            upload_record["empirical_details"], {}
        ),
        "scoring_algorithm_version": upload_record["scoring_algorithm_version"],
        "quality_profile_version": upload_record["quality_profile_version"],
        "quality_profile_checksum": upload_record["quality_profile_checksum"],
        "reference_recording_count": upload_record["reference_recording_count"],
    }
    if upload_record["analysis_purpose"] == "settings_suggestion":
        response_data["settings_recommendation"] = (
            settings_recommendation_service.stored_recommendation_payload(
                upload_record
            )
        )
    return jsonify(response_data)


@require_auth("admin")
def get_audit_logs():
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        """SELECT audit_log_id AS id, user_id, action, resource_type, resource_id, result, ip_address, created_at
           FROM audit_log ORDER BY created_at DESC LIMIT 200"""
    )
    rows = cursor.fetchall()
    cursor.close()
    conn.close()
    return jsonify(rows)


@require_auth("admin")
def get_request_logs():
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        """SELECT request_log_id AS id, user_id, method, path, endpoint,
                  status_code, duration_ms, ip_address, user_agent, created_at
           FROM api_request_log
           ORDER BY created_at DESC, request_log_id DESC
           LIMIT 200"""
    )
    rows = cursor.fetchall()
    cursor.close()
    conn.close()
    return jsonify(rows)


for route_group in (
    system_routes,
    admin_data_routes,
    auth_routes,
    users_routes,
    assessments_routes,
    audio_analysis_routes,
    audit_routes,
    settings_recommendation_routes,
):
    app.register_blueprint(route_group)
