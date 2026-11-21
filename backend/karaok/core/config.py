"""Environment-backed configuration for the KaraOK API."""

import os
from pathlib import Path

from dotenv import load_dotenv


_environment_file = os.getenv("KARAOK_ENV_FILE")
if _environment_file:
    load_dotenv(dotenv_path=_environment_file)
else:
    load_dotenv()

BACKEND_DIR = Path(__file__).resolve().parents[2]
TRUST_PROXY = os.getenv("TRUST_PROXY", "false").lower() == "true"
CORS_ORIGINS = [
    origin.strip()
    for origin in os.getenv("CORS_ORIGINS", "http://localhost:*").split(",")
    if origin.strip()
]
RATELIMIT_STORAGE_URI = os.getenv("RATELIMIT_STORAGE_URI", "memory://")

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "database": os.getenv("DB_NAME", "karaok_db"),
    "user": os.getenv("DB_USER", "root"),
    "password": os.getenv("DB_PASSWORD", ""),
    "port": int(os.getenv("DB_PORT", "3306")),
}

# The Data Administration API uses a distinct database identity. Keeping it
# separate from the public application account makes its CRUD permissions
# explicit and independently revocable. It never receives schema privileges.
ADMIN_DB_CONFIG = {
    "host": os.getenv("ADMIN_DB_HOST", os.getenv("DB_HOST", "localhost")),
    "database": os.getenv("ADMIN_DB_NAME", os.getenv("DB_NAME", "karaok_db")),
    "user": os.getenv("ADMIN_DB_USER", ""),
    "password": os.getenv("ADMIN_DB_PASSWORD", ""),
    "port": int(os.getenv("ADMIN_DB_PORT", os.getenv("DB_PORT", "3306"))),
}
ADMIN_DATA_API_ENABLED = os.getenv("ADMIN_DATA_API_ENABLED", "false").lower() == "true"
ADMIN_DATA_API_KEY_HASH = os.getenv("ADMIN_DATA_API_KEY_HASH", "").strip().lower()
ADMIN_DATA_API_QUERY_TIMEOUT_MS = int(os.getenv("ADMIN_DATA_API_QUERY_TIMEOUT_MS", "5000"))
SETTINGS_RECOMMENDATIONS_ENABLED = (
    os.getenv("SETTINGS_RECOMMENDATIONS_ENABLED", "false").lower() == "true"
)
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
OTP_RESEND_COOLDOWN_SECONDS = int(os.getenv("OTP_RESEND_COOLDOWN_SECONDS", "300"))
OTP_MAX_SENDS_PER_EMAIL_PER_HOUR = int(os.getenv("OTP_MAX_SENDS_PER_EMAIL_PER_HOUR", "4"))
OTP_MAX_SENDS_PER_DEVICE_PER_HOUR = int(os.getenv("OTP_MAX_SENDS_PER_DEVICE_PER_HOUR", "10"))
OTP_MAX_SENDS_PER_IP_PER_HOUR = int(os.getenv("OTP_MAX_SENDS_PER_IP_PER_HOUR", "30"))
OTP_MAX_VERIFY_ATTEMPTS = int(os.getenv("OTP_MAX_VERIFY_ATTEMPTS", "5"))
AUTH_BURST_LIMIT = int(os.getenv("AUTH_BURST_LIMIT", "5"))
AUTH_BURST_WINDOW_SECONDS = int(os.getenv("AUTH_BURST_WINDOW_SECONDS", "30"))
AUTH_LOCKOUT_FIRST_SECONDS = int(os.getenv("AUTH_LOCKOUT_FIRST_SECONDS", "30"))
AUTH_LOCKOUT_REPEAT_SECONDS = int(os.getenv("AUTH_LOCKOUT_REPEAT_SECONDS", "60"))
AUTH_STRIKE_RESET_SECONDS = int(os.getenv("AUTH_STRIKE_RESET_SECONDS", "900"))
AUTH_IP_CEILING_PER_MINUTE = int(os.getenv("AUTH_IP_CEILING_PER_MINUTE", "120"))
LOGIN_ACCOUNT_FAIL_LIMIT = int(os.getenv("LOGIN_ACCOUNT_FAIL_LIMIT", "20"))
LOGIN_ACCOUNT_FAIL_WINDOW_SECONDS = int(os.getenv("LOGIN_ACCOUNT_FAIL_WINDOW_SECONDS", "900"))
ALLOWED_EMAIL_DOMAINS = tuple(
    domain.strip().lower()
    for domain in os.getenv(
        "ALLOWED_EMAIL_DOMAINS",
        "gmail.com,googlemail.com,yahoo.com,yahoo.com.ph,ymail.com,rocketmail.com,"
        "outlook.com,hotmail.com,live.com,msn.com,icloud.com,me.com,mac.com,"
        "proton.me,protonmail.com,aol.com,zoho.com,gmx.com,mail.com,yandex.com",
    ).split(",")
    if domain.strip()
)
DEV_MODE = os.getenv("DEV_MODE", "false").lower() == "true"
EXPOSE_REGISTRATION_OTP = (
    os.getenv("EXPOSE_REGISTRATION_OTP", "false").lower() == "true"
)

MAX_AUDIO_BYTES = int(os.getenv("MAX_AUDIO_BYTES", str(26 * 1024 * 1024)))
MAX_PROFILE_IMAGE_BYTES = int(
    os.getenv("MAX_PROFILE_IMAGE_BYTES", str(5 * 1024 * 1024))
)
MAX_AUDIO_SECONDS = 300
AUDIO_UPLOAD_DIR = os.path.abspath(
    os.getenv("AUDIO_UPLOAD_DIR") or BACKEND_DIR / "uploads"
)
ANALYSIS_OUTPUT_DIR = os.path.abspath(
    os.getenv("AUDIO_ANALYSIS_OUTPUT_DIR")
    or Path(AUDIO_UPLOAD_DIR) / "_analysis"
)
AUDIO_ANALYZER_PATH = os.path.abspath(
    os.getenv("AUDIO_ANALYZER_PATH") or BACKEND_DIR / "audio_analyzer.py"
)
AUDIO_ANALYZER_SETTINGS_PATH = os.path.abspath(
    os.getenv("AUDIO_ANALYZER_SETTINGS_PATH")
    or BACKEND_DIR / "audio_analyzer_settings.json"
)
AUDIO_ANALYSIS_TIMEOUT_SECONDS = int(
    os.getenv("AUDIO_ANALYSIS_TIMEOUT_SECONDS", "300")
)
# Nightly retention cleanup (scripts/purge_old_records.py). 0 keeps forever.
REQUEST_LOG_RETENTION_DAYS = int(os.getenv("REQUEST_LOG_RETENTION_DAYS", "90"))
AUDIT_LOG_RETENTION_DAYS = int(os.getenv("AUDIT_LOG_RETENTION_DAYS", "365"))
VISUALIZATION_RETENTION_DAYS = int(os.getenv("VISUALIZATION_RETENTION_DAYS", "0"))
ALLOWED_ANALYSIS_PURPOSES = {"quality_evaluation", "settings_suggestion"}
ANALYZER_COMPLETED_EXIT_CODES = {0, 3}
ALLOWED_AUDIO_EXTENSIONS = {"wav", "mp3", "m4a", "aac", "ogg", "flac"}

APP_HOST = os.getenv("APP_HOST", "127.0.0.1")
APP_PORT = int(os.getenv("APP_PORT", "5000"))
FLASK_DEBUG = os.getenv("FLASK_DEBUG", "false").lower() == "true"
