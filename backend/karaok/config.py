"""Environment-backed configuration for the KaraOK API."""

import os
from pathlib import Path

from dotenv import load_dotenv


load_dotenv()

BACKEND_DIR = Path(__file__).resolve().parents[1]
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
EXPOSE_REGISTRATION_OTP = (
    os.getenv("EXPOSE_REGISTRATION_OTP", "false").lower() == "true"
)

MAX_AUDIO_BYTES = int(os.getenv("MAX_AUDIO_BYTES", str(25 * 1024 * 1024)))
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
ALLOWED_ANALYSIS_PURPOSES = {"quality_evaluation", "settings_suggestion"}
ANALYZER_COMPLETED_EXIT_CODES = {0, 3}
ALLOWED_AUDIO_EXTENSIONS = {"wav", "mp3", "m4a", "aac", "ogg", "flac"}

APP_HOST = os.getenv("APP_HOST", "127.0.0.1")
APP_PORT = int(os.getenv("APP_PORT", "5000"))
FLASK_DEBUG = os.getenv("FLASK_DEBUG", "false").lower() == "true"
