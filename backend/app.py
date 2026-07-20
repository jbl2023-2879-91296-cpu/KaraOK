from __future__ import annotations

from datetime import datetime, timedelta, timezone
from functools import wraps
import hashlib
import json
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

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError
from dotenv import load_dotenv
from flask import Flask, g, jsonify, request
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
import jwt
import mysql.connector
from mutagen import File as MutagenFile
from mysql.connector import Error, IntegrityError
from werkzeug.middleware.proxy_fix import ProxyFix
from werkzeug.utils import secure_filename

from audio_thresholds import evaluate_features, load_thresholds


load_dotenv()

app = Flask(__name__)
if os.getenv("TRUST_PROXY", "false").lower() == "true":
    # The production service accepts traffic only from one local Nginx proxy.
    app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)
allowed_origins = [
    origin.strip()
    for origin in os.getenv("CORS_ORIGINS", "http://localhost:*").split(",")
    if origin.strip()
]
CORS(app, resources={r"/api/*": {"origins": allowed_origins}})
limiter = Limiter(
    get_remote_address,
    app=app,
    storage_uri=os.getenv("RATELIMIT_STORAGE_URI", "memory://"),
    default_limits=["200 per hour"],
)

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "database": os.getenv("DB_NAME", "karaok_db"),
    "user": os.getenv("DB_USER", "root"),
    "password": os.getenv("DB_PASSWORD", ""),
    "port": int(os.getenv("DB_PORT", "3306")),
}
JWT_SECRET = os.getenv("JWT_SECRET", "")
JWT_ISSUER = "karaok-api"
ACCESS_TOKEN_MINUTES = int(os.getenv("ACCESS_TOKEN_MINUTES", "15"))
REFRESH_TOKEN_DAYS = int(os.getenv("REFRESH_TOKEN_DAYS", "7"))
SMTP_HOST = os.getenv("SMTP_HOST", "")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USERNAME = os.getenv("SMTP_USERNAME", "")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "")
SMTP_FROM = os.getenv("SMTP_FROM", SMTP_USERNAME)
OTP_MINUTES = int(os.getenv("REGISTRATION_OTP_MINUTES", "10"))
DEV_MODE = os.getenv("DEV_MODE", "false").lower() == "true"
EXPOSE_REGISTRATION_OTP = os.getenv("EXPOSE_REGISTRATION_OTP", "false").lower() == "true"
MAX_AUDIO_BYTES = int(os.getenv("MAX_AUDIO_BYTES", str(25 * 1024 * 1024)))
MAX_AUDIO_SECONDS = 300
AUDIO_UPLOAD_DIR = os.path.abspath(
    os.getenv("AUDIO_UPLOAD_DIR")
    or os.path.join(os.path.dirname(__file__), "uploads")
)
ANALYSIS_OUTPUT_DIR = os.path.abspath(
    os.getenv("AUDIO_ANALYSIS_OUTPUT_DIR")
    or os.path.join(AUDIO_UPLOAD_DIR, "_analysis")
)
AUDIO_ANALYZER_PATH = os.path.abspath(
    os.getenv("AUDIO_ANALYZER_PATH")
    or os.path.join(os.path.dirname(__file__), "audio_analyzer.py")
)
AUDIO_ANALYZER_SETTINGS_PATH = os.path.abspath(
    os.getenv("AUDIO_ANALYZER_SETTINGS_PATH")
    or os.path.join(os.path.dirname(__file__), "audio_analyzer_settings.json")
)
AUDIO_ANALYSIS_TIMEOUT_SECONDS = int(
    os.getenv("AUDIO_ANALYSIS_TIMEOUT_SECONDS", "300")
)
ALLOWED_ANALYSIS_PURPOSES = {"quality_evaluation", "settings_suggestion"}
ANALYZER_COMPLETED_EXIT_CODES = {0, 3}
ALLOWED_AUDIO_EXTENSIONS = {"wav", "mp3", "m4a", "aac", "ogg", "flac"}
app.config["MAX_CONTENT_LENGTH"] = MAX_AUDIO_BYTES + (1024 * 1024)

password_hasher = PasswordHasher(time_cost=2, memory_cost=19456, parallelism=1)
EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
VALID_ROLES = {"technician", "owner", "admin"}
SELF_REGISTER_ROLES = {"owner", "technician"}
VALID_STATUSES = {"Acceptable", "Needs Improvement", "Problematic"}
EMPIRICAL_RESULT_STATUSES = {
    "good": "Acceptable",
    "good_but_needs_improvement": "Needs Improvement",
    "bad": "Problematic",
}


class AudioAnalyzerExecutionError(RuntimeError):
    def __init__(self, message: str, dump: dict[str, Any]):
        super().__init__(message)
        self.dump = dump


def get_db():
    return mysql.connector.connect(**DB_CONFIG)


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def json_body() -> dict[str, Any]:
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        raise ValueError("A JSON object is required")
    return data


def clean_text(value: Any, field: str, minimum: int, maximum: int) -> str:
    if not isinstance(value, str):
        raise ValueError(f"{field} must be text")
    cleaned = " ".join(value.strip().split())
    if not minimum <= len(cleaned) <= maximum:
        raise ValueError(f"{field} must be {minimum}-{maximum} characters")
    return cleaned


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
    root = Path(ANALYSIS_OUTPUT_DIR).resolve()
    destination = (root / str(user_id) / str(assessment_id)).resolve()
    if os.path.commonpath((str(root), str(destination))) != str(root):
        raise RuntimeError("Invalid analysis output path")
    destination.mkdir(parents=True, exist_ok=True)
    return destination


def cleanup_audio_artifacts(
    user_id: int,
    assessment_id: int,
    audio_file_path: str | None,
) -> None:
    """Remove a deleted assessment's upload and analyzer output safely."""
    upload_root = Path(AUDIO_UPLOAD_DIR).resolve()
    if audio_file_path:
        upload_path = Path(audio_file_path).resolve()
        if os.path.commonpath((str(upload_root), str(upload_path))) != str(upload_root):
            raise RuntimeError("Audio upload path is outside the configured root")
        upload_path.unlink(missing_ok=True)

    analysis_root = Path(ANALYSIS_OUTPUT_DIR).resolve()
    analysis_path = (analysis_root / str(user_id) / str(assessment_id)).resolve()
    if os.path.commonpath((str(analysis_root), str(analysis_path))) != str(analysis_root):
        raise RuntimeError("Analysis output path is outside the configured root")
    if analysis_path.is_dir():
        shutil.rmtree(analysis_path)


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
        "--no-save-plots",
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
    """Analyze an upload without retaining analyzer working files on the server."""
    try:
        return _run_audio_analyzer(
            audio_path,
            user_id=user_id,
            assessment_id=assessment_id,
            original_name=original_name,
            analysis_purpose=analysis_purpose,
        )
    finally:
        root = Path(ANALYSIS_OUTPUT_DIR).resolve()
        destination = (root / str(user_id) / str(assessment_id)).resolve()
        if os.path.commonpath((str(root), str(destination))) != str(root):
            app.logger.error("Refused to clean an invalid analyzer working path")
        elif destination.is_dir():
            shutil.rmtree(destination, ignore_errors=True)


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
    }


def persist_audio_analysis(
    assessment_id: int,
    upload_id: int,
    dump: dict[str, Any],
) -> dict[str, Any]:
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
    algorithm_version = empirical.get("algorithm_version")
    reference_recording_count = empirical.get("reference_recording_count")

    conn = get_db()
    cursor = conn.cursor()
    try:
        cursor.execute(
            """SELECT gp.preset_id
               FROM genre_preset gp
               JOIN audio_upload au
                 ON au.upload_id = %s
                AND au.genre_name IS NOT NULL
                AND LOWER(gp.genre_name) = LOWER(au.genre_name)
               LIMIT 1""",
            (upload_id,),
        )
        preset = cursor.fetchone()
        cursor.execute(
            """INSERT INTO audio_analysis_result
               (assessment_id, threshold_id, preset_id, quality_score,
                noise_level, distortion_level, bass, treble, loudness,
                sharpness, flatness, empirical_status,
                worst_feature_status, worst_features, empirical_details,
                scoring_algorithm_version, reference_recording_count)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                       %s, %s, %s, %s, %s, %s)""",
            (
                assessment_id,
                None,
                preset[0] if preset else None,
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
                reference_recording_count,
            ),
        )
        cursor.execute(
            """UPDATE assessment
               SET assessment_status = 'Completed', result_status = %s,
                   processing_time = %s, api_reference = %s,
                   audio_file_path = NULL
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


def clean_email(value: Any) -> str:
    email = clean_text(value, "email", 5, 254).lower()
    if not EMAIL_RE.fullmatch(email):
        raise ValueError("email is invalid")
    return email


def validate_password(password: Any) -> str:
    if not isinstance(password, str) or not 12 <= len(password) <= 128:
        raise ValueError("password must be 12-128 characters")
    if not (re.search(r"[A-Z]", password) and re.search(r"[a-z]", password)):
        raise ValueError("password must include uppercase and lowercase letters")
    if not re.search(r"\d", password) or not re.search(r"[^A-Za-z0-9]", password):
        raise ValueError("password must include a number and symbol")
    return password


def generate_temporary_password(length: int = 20) -> str:
    """Generate a policy-compliant password intended for one-time login."""
    uppercase = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    lowercase = "abcdefghijkmnopqrstuvwxyz"
    digits = "23456789"
    symbols = "!@#$%&*-_"
    characters = uppercase + lowercase + digits + symbols
    password = [
        secrets.choice(uppercase),
        secrets.choice(lowercase),
        secrets.choice(digits),
        secrets.choice(symbols),
    ]
    password.extend(secrets.choice(characters) for _ in range(length - len(password)))
    secrets.SystemRandom().shuffle(password)
    return "".join(password)


def bounded_number(value: Any, field: str, minimum: float, maximum: float) -> float:
    if isinstance(value, bool):
        raise ValueError(f"{field} must be numeric")
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{field} must be numeric") from exc
    if not minimum <= number <= maximum:
        raise ValueError(f"{field} must be between {minimum} and {maximum}")
    return number


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


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
                (request.endpoint or "")[:100] or None,
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
    now = utcnow()
    expires = now + timedelta(minutes=ACCESS_TOKEN_MINUTES)
    payload = {
        "sub": str(user["user_id"]),
        "role": user["user_type"],
        "iss": JWT_ISSUER,
        "iat": now,
        "nbf": now,
        "exp": expires,
        "jti": secrets.token_hex(16),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256"), int(expires.timestamp())


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
            "user": {
                "id": user["user_id"],
                "name": user["username"],
                "email": user["email"],
                "user_type": user["user_type"],
                "requires_password_change": bool(user.get("requires_password_change", False)),
            },
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
    updated_epoch = account.get("security_updated_at_epoch")
    if updated_epoch is None:
        return False
    return int(payload["iat"]) < int(updated_epoch)


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
            if g.requires_password_change and request.endpoint != "change_password":
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


@app.after_request
def security_headers(response):
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    return response


@app.get("/api/health")
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


@app.post("/api/auth/register")
@limiter.limit("5 per hour")
def register():
    data = json_body()
    name = clean_text(data.get("name"), "name", 2, 50)
    email = clean_email(data.get("email"))
    password = validate_password(data.get("password"))
    user_type = data.get("user_type", "owner")
    if user_type not in SELF_REGISTER_ROLES:
        raise ValueError("public registration allows owner or technician accounts only")

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
            (name,),
        )
        username_user = cursor.fetchone()

        if email_user and (
            email_user["email_verified_at"] is not None
            or email_user["username"] != name
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
                """UPDATE user SET password = %s, role = %s
                   WHERE user_id = %s AND email_verified_at IS NULL""",
                (password_hash, user_type, user_id),
            )
        else:
            cursor.execute(
                """INSERT INTO user
                   (username, email, password, role, email_verified_at)
                   VALUES (%s, %s, %s, %s, NULL)""",
                (name, email, password_hash, user_type),
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
    except (IntegrityError, smtplib.SMTPException, RuntimeError):
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


@app.post("/api/auth/register/verify")
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
                  user.user_id, user.username, user.email, user.role
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
        "email": pending["email"],
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


@app.post("/api/auth/login")
@limiter.limit("5 per minute")
def login():
    data = json_body()
    raw_identifier = data.get("identifier", data.get("email"))
    identifier = clean_text(raw_identifier, "username or email", 2, 254)
    is_email = EMAIL_RE.fullmatch(identifier) is not None
    if is_email:
        identifier = clean_email(identifier)
    elif len(identifier) > 50:
        raise ValueError("username must be 2-50 characters")
    password = data.get("password")
    if not isinstance(password, str) or len(password) > 128:
        raise ValueError("password is invalid")

    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    login_column = "email" if is_email else "username"
    cursor.execute(
        f"""SELECT u.user_id, u.username, u.email, u.role AS user_type,
                   u.password AS password_hash, u.is_active, u.email_verified_at,
                   u.requires_password_change
            FROM user u WHERE u.{login_column} = %s LIMIT 1""",
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


@app.post("/api/auth/refresh")
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
                  u.username, u.email, u.role AS user_type, u.is_active,
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


@app.post("/api/auth/logout")
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


@app.post("/api/auth/forgot-password")
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


@app.post("/api/auth/change-password")
@limiter.limit("10 per hour", exempt_when=lambda: DEV_MODE)
@require_auth("technician", "owner", "admin")
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


@app.get("/api/users")
@require_auth("admin")
def get_users():
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        """SELECT user_id AS id, username AS name, email,
                  role AS user_type, is_active, email_verified_at, created_at
           FROM user ORDER BY created_at DESC"""
    )
    rows = cursor.fetchall()
    cursor.close()
    conn.close()
    return jsonify(rows)


@app.get("/api/audio-tests")
@require_auth("technician", "owner")
def get_audio_tests():
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        """SELECT a.assessment_id AS id, a.test_name,
                  r.quality_score AS score, r.noise_level,
                  r.distortion_level, r.bass, r.treble, r.loudness,
                  r.sharpness, r.flatness, a.result_status AS status,
                  a.assessment_status, a.analysis_purpose, a.duration_seconds,
                  a.assessment_date AS created_at
           FROM assessment a
           LEFT JOIN audio_analysis_result r
             ON r.assessment_id = a.assessment_id
           WHERE a.user_id = %s
           ORDER BY a.assessment_date DESC""",
        (g.user_id,),
    )
    rows = [_enrich_audio_test_row(row) for row in cursor.fetchall()]
    cursor.close()
    conn.close()
    return jsonify(rows)


@app.get("/api/audio-tests/<int:test_id>")
@require_auth("technician", "owner")
def get_audio_test(test_id: int):
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        """SELECT a.assessment_id AS id, a.test_name,
                  r.quality_score AS score, r.noise_level,
                  r.distortion_level, r.bass, r.treble, r.loudness,
                  r.sharpness, r.flatness, a.result_status AS status,
                  a.assessment_status, a.analysis_purpose, a.duration_seconds,
                  a.assessment_date AS created_at
           FROM assessment a
           LEFT JOIN audio_analysis_result r
             ON r.assessment_id = a.assessment_id
           WHERE a.assessment_id = %s AND a.user_id = %s""",
        (test_id, g.user_id),
    )
    row = cursor.fetchone()
    cursor.close()
    conn.close()
    if not row:
        return jsonify({"error": "Not found"}), 404
    return jsonify(_enrich_audio_test_row(row)), 200


@app.post("/api/audio-tests")
@require_auth("technician", "owner")
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
           (assessment_id, threshold_id, preset_id, quality_score, noise_level, distortion_level)
           VALUES (%s, %s, %s, %s, %s, %s)""",
        (test_id, None, None, score, noise, distortion),
    )
    conn.commit()
    cursor.close()
    conn.close()
    audit("audio_test_created", "success", user_id=g.user_id, resource_type="audio_test", resource_id=test_id)
    return jsonify({"id": test_id, "test_name": test_name, "score": score}), 201


@app.delete("/api/audio-tests/<int:test_id>")
@require_auth("technician", "owner")
def delete_audio_test(test_id: int):
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        """SELECT audio_file_path FROM assessment
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
        cleanup_audio_artifacts(
            g.user_id,
            test_id,
            assessment.get("audio_file_path"),
        )
    except (OSError, RuntimeError):
        app.logger.exception("Deleted assessment artifact cleanup failed")
    audit("audio_test_deleted", "success", user_id=g.user_id, resource_type="audio_test", resource_id=test_id)
    return jsonify({"message": "Deleted"})


@app.get("/api/genre-settings")
@require_auth("technician", "owner")
def get_genre_settings():
    genre = request.args.get("genre")
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    if genre:
        genre = clean_text(genre, "genre", 2, 50)
        cursor.execute("SELECT * FROM user_genre_setting WHERE genre_name = %s AND user_id = %s ORDER BY updated_at DESC LIMIT 1", (genre, g.user_id))
        result = cursor.fetchone()
    else:
        cursor.execute("SELECT * FROM user_genre_setting WHERE user_id = %s ORDER BY genre_name", (g.user_id,))
        result = cursor.fetchall()
    cursor.close()
    conn.close()
    if genre and not result:
        return jsonify({"error": "No settings for this genre"}), 404
    return jsonify(result)


@app.post("/api/genre-settings")
@require_auth("owner")
def save_genre_settings():
    data = json_body()
    genre = clean_text(data.get("genre"), "genre", 2, 50)
    values = [int(bounded_number(data.get(field), field, 0, 100)) for field in ("volume", "bass", "treble", "flatness", "sharpness")]
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        """SELECT preset_id FROM genre_preset
           WHERE LOWER(genre_name) = LOWER(%s) LIMIT 1""",
        (genre,),
    )
    preset = cursor.fetchone()
    cursor.execute(
        """INSERT INTO user_genre_setting
           (user_id, preset_id, genre_name, volume, bass, treble,
            flatness, sharpness)
           VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
        (g.user_id, preset[0] if preset else None, genre, *values),
    )
    conn.commit()
    setting_id = cursor.lastrowid
    cursor.close()
    conn.close()
    audit("genre_settings_saved", "success", user_id=g.user_id, resource_type="genre_setting", resource_id=setting_id)
    return jsonify({"id": setting_id, "genre": genre}), 201


@app.get("/api/audio-uploads")
@require_auth("technician", "owner")
def get_audio_uploads():
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        """SELECT au.upload_id AS id, au.file_name,
                  au.genre_name AS genre, au.score, au.status,
                  au.size_bytes, au.mime_type, a.duration_seconds,
                  a.analysis_purpose, au.created_at
           FROM audio_upload au
           JOIN assessment a ON a.assessment_id = au.assessment_id
           WHERE a.user_id = %s ORDER BY au.created_at DESC""",
        (g.user_id,),
    )
    rows = cursor.fetchall()
    cursor.close()
    conn.close()
    return jsonify(rows)


@app.post("/api/guest/audio-analysis")
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
            status = "Completed"
        except AudioAnalyzerExecutionError as error:
            analysis_dump = error.dump
            analysis_summary = None
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
            status = "Failed"
    finally:
        try:
            cleanup_audio_artifacts(0, work_id, stored_path)
        except (OSError, RuntimeError):
            app.logger.exception("Transient guest audio cleanup failed")

    upload_details = analysis_dump.get("upload")
    if isinstance(upload_details, dict):
        upload_details["assessment_id"] = None
    return (
        jsonify(
            {
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
                    analysis_summary["distortion_level"]
                    if analysis_summary
                    else None
                ),
                "bass": analysis_summary["bass"] if analysis_summary else None,
                "treble": analysis_summary["treble"] if analysis_summary else None,
                "loudness": (
                    analysis_summary["loudness"] if analysis_summary else None
                ),
                "sharpness": (
                    analysis_summary["sharpness"] if analysis_summary else None
                ),
                "flatness": (
                    analysis_summary["flatness"] if analysis_summary else None
                ),
                "empirical_quality": (
                    analysis_summary["empirical_quality"]
                    if analysis_summary
                    else None
                ),
                "analysis_purpose": analysis_purpose,
                "analysis_dump": analysis_dump,
            }
        ),
        201,
    )


@app.post("/api/audio-uploads")
@require_auth("technician", "owner")
def create_audio_upload():
    upload = request.files.get("audio")
    if upload is None or not upload.filename:
        return jsonify({"error": "A multipart audio file is required in the 'audio' field"}), 400
    original_name = secure_filename(upload.filename)
    extension = original_name.rsplit(".", 1)[-1].lower() if "." in original_name else ""
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
    try:
        analysis_dump = run_audio_analyzer(
            stored_path,
            user_id=g.user_id,
            assessment_id=assessment_id,
            original_name=original_name,
            analysis_purpose=analysis_purpose,
        )
        analysis_summary = persist_audio_analysis(
            assessment_id,
            upload_id,
            analysis_dump,
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
            cleanup_audio_artifacts(g.user_id, assessment_id, stored_path)
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
    return (
        jsonify(
            {
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
                    analysis_summary["distortion_level"]
                    if analysis_summary
                    else None
                ),
                "bass": analysis_summary["bass"] if analysis_summary else None,
                "treble": analysis_summary["treble"] if analysis_summary else None,
                "loudness": (
                    analysis_summary["loudness"] if analysis_summary else None
                ),
                "sharpness": (
                    analysis_summary["sharpness"] if analysis_summary else None
                ),
                "flatness": (
                    analysis_summary["flatness"] if analysis_summary else None
                ),
                "empirical_quality": (
                    analysis_summary["empirical_quality"]
                    if analysis_summary
                    else None
                ),
                "analysis_purpose": analysis_purpose,
                "analysis_dump_url": f"/api/audio-uploads/{upload_id}/analysis-dump",
                "analysis_dump": analysis_dump,
            }
        ),
        201,
    )


@app.get("/api/audio-uploads/<int:upload_id>/analysis-dump")
@require_auth("technician", "owner")
def get_audio_analysis_dump(upload_id: int):
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        """SELECT au.assessment_id, au.file_name,
                  a.analysis_purpose, a.assessment_status, a.result_status,
                  r.quality_score, r.noise_level, r.distortion_level,
                  r.bass, r.treble, r.loudness, r.sharpness, r.flatness,
                  r.empirical_status, r.worst_feature_status,
                  r.worst_features, r.empirical_details,
                  r.scoring_algorithm_version, r.reference_recording_count
           FROM audio_upload au
           JOIN assessment a ON a.assessment_id = au.assessment_id
           LEFT JOIN audio_analysis_result r
             ON r.assessment_id = a.assessment_id
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

    return jsonify(
        {
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
            "scoring_algorithm_version": upload_record[
                "scoring_algorithm_version"
            ],
            "reference_recording_count": upload_record[
                "reference_recording_count"
            ],
        }
    )


@app.get("/api/audit-logs")
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


@app.get("/api/request-logs")
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


if __name__ == "__main__":
    if not JWT_SECRET or len(JWT_SECRET) < 32:
        raise RuntimeError("JWT_SECRET must be set to a random value of at least 32 characters")
    app.run(host=os.getenv("APP_HOST", "127.0.0.1"), port=int(os.getenv("APP_PORT", "5000")), debug=os.getenv("FLASK_DEBUG", "false").lower() == "true")
