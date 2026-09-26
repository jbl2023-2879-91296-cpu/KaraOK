"""Historical app-module exports; no feature implementation belongs here."""

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
from .core.runtime import app, limiter
from karaok.audio_pipeline.pipeline import MIDI_RENDERED_AUDIO_MESSAGE
VALID_ROLES = {"user", "admin"}
from karaok.auth.accounts import SELF_REGISTER_ROLE
from karaok.results.assessments import VALID_STATUSES
from karaok.core.quality import EMPIRICAL_RESULT_STATUSES
from karaok.core.quality import RESULT_EMPIRICAL_STATUSES
from karaok.results.assessments import SETTINGS_RECOMMENDATION_SELECT_COLUMNS
from karaok.audio_pipeline.pipeline import AudioAnalyzerExecutionError
from karaok.core.time import utcnow
from karaok.core.accounts import _clean_profile_image
from karaok.core.accounts import _clean_birthday
from karaok.core.accounts import _clean_phone
from karaok.core.accounts import _profile_response
from karaok.audio_pipeline.pipeline import AudioDurationError
from karaok.audio_pipeline.pipeline import audio_duration_seconds
from karaok.core.artifacts import _analysis_directory
from karaok.core.artifacts import cleanup_audio_artifacts
from karaok.core.artifacts import _remove_temporary_audio
from karaok.core.artifacts import _analysis_artifact_relative_path
from karaok.audio_pipeline.pipeline import _visualization_paths
from karaok.audio_pipeline.pipeline import _guest_visualization_images
from karaok.audio_pipeline.pipeline import _process_text
from karaok.audio_pipeline.pipeline import _execute_analyzer_command
from karaok.audio_pipeline.pipeline import _run_audio_analyzer
from karaok.audio_pipeline.pipeline import run_audio_analyzer
from karaok.core.values import _nested_number
from karaok.audio_pipeline.pipeline import _empirical_feature_values
from karaok.core.quality import _score_empirical_values
from karaok.audio_pipeline.pipeline import _score_analyzer_output
from karaok.core.quality import _empirical_result_status
from karaok.results.presentation import _finite_stored_number
from karaok.results.presentation import _decoded_object
from karaok.results.presentation import _decoded_string_list
from karaok.results.presentation import _valid_detail_provenance
from karaok.results.presentation import _stored_empirical_result
from karaok.results.presentation import _enrich_audio_test_row
from karaok.results.presentation import _attach_stored_recommendation
from karaok.audio_pipeline.pipeline import _analysis_safety_signals
from karaok.audio_pipeline.pipeline import summarize_audio_analysis
from karaok.audio_pipeline.pipeline import persist_audio_analysis
from karaok.results.records import mark_audio_analysis_failed, save_audio_analysis, create_audio_upload_records
from karaok.auth.mail import send_registration_otp
from karaok.auth.mail import send_temporary_password_email
from karaok.core.request_context import client_ip
from karaok.core.audit import audit
from karaok.auth.tokens import issue_access_token
from karaok.auth.tokens import create_refresh_token
from karaok.auth.accounts import auth_response
from karaok.auth.tokens import _token_precedes_security_update
from karaok.auth.access import require_auth
from karaok.auth.accounts import register
from karaok.auth.accounts import verify_registration
from karaok.auth.accounts import login
from karaok.auth.accounts import refresh
from karaok.auth.accounts import logout
from karaok.auth.accounts import forgot_password
from karaok.auth.accounts import change_password
from karaok.users.profiles import update_profile
from karaok.results.assessments import get_audio_tests
from karaok.results.assessments import get_audio_test
from karaok.results.assessments import create_audio_test
from karaok.results.assessments import delete_audio_test
from karaok.results.assessments import get_audio_uploads
from karaok.audio_pipeline.pipeline import create_guest_audio_analysis
from karaok.audio_pipeline.pipeline import create_audio_upload
from karaok.results.visualizations import get_audio_visualization
from karaok.results.assessments import get_audio_analysis_dump
from karaok.admin.users import get_users
from karaok.admin.logs import get_audit_logs
from karaok.admin.logs import get_request_logs
from karaok.system.health import health
from karaok.request_logging import begin_api_request_log
from karaok.request_logging import complete_api_request_log

__all__ = [name for name in globals() if not name.startswith("__")]
