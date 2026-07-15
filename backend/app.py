from __future__ import annotations

from datetime import datetime, timedelta, timezone
from functools import wraps
import hashlib
import os
import re
import secrets
import smtplib
from email.message import EmailMessage
from typing import Any, Callable
from urllib.parse import urlencode

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError
from dotenv import load_dotenv
from flask import Flask, g, jsonify, render_template, request
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
import jwt
import mysql.connector
from mysql.connector import Error, IntegrityError


load_dotenv()

app = Flask(__name__)
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
RESET_TOKEN_MINUTES = int(os.getenv("RESET_TOKEN_MINUTES", "15"))
EXPOSE_RESET_TOKEN = os.getenv("EXPOSE_RESET_TOKEN", "false").lower() == "true"
RESET_LINK_BASE = os.getenv("RESET_LINK_BASE", "http://127.0.0.1:5000/reset-password")
SMTP_HOST = os.getenv("SMTP_HOST", "")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USERNAME = os.getenv("SMTP_USERNAME", "")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "")
SMTP_FROM = os.getenv("SMTP_FROM", SMTP_USERNAME)
OTP_MINUTES = int(os.getenv("REGISTRATION_OTP_MINUTES", "10"))
DEV_MODE = os.getenv("DEV_MODE", "false").lower() == "true"
EXPOSE_REGISTRATION_OTP = os.getenv("EXPOSE_REGISTRATION_OTP", "false").lower() == "true"

password_hasher = PasswordHasher(time_cost=2, memory_cost=19456, parallelism=1)
EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
VALID_ROLES = {"technician", "owner"}
VALID_STATUSES = {"Acceptable", "Needs Improvement"}


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


def send_password_reset_email(email: str, token: str) -> None:
    if not all((SMTP_HOST, SMTP_USERNAME, SMTP_PASSWORD, SMTP_FROM)):
        raise RuntimeError("SMTP is not configured")
    separator = "&" if "?" in RESET_LINK_BASE else "?"
    reset_link = f"{RESET_LINK_BASE}{separator}{urlencode({'token': token})}"
    message = EmailMessage()
    message["Subject"] = "Reset your KaraOK password"
    message["From"] = SMTP_FROM
    message["To"] = email
    message.set_content(
        f"""A password reset was requested for your KaraOK account.

Open this single-use link to choose a new password:

{reset_link}

This link expires in {RESET_TOKEN_MINUTES} minutes. If you did not request a
password reset, you can safely ignore this email. Never share this link.
"""
    )
    with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=15) as server:
        server.starttls()
        server.login(SMTP_USERNAME, SMTP_PASSWORD)
        server.send_message(message)


def client_ip() -> str:
    return request.headers.get("X-Forwarded-For", request.remote_addr or "")[:45]


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
    return jsonify(
        {
            "user": {
                "id": user["user_id"],
                "name": user["username"],
                "email": user["email"],
                "user_type": user["user_type"],
            },
            "access_token": access_token,
            "access_expires_at": access_expires_at,
            "refresh_token": refresh_token,
            "refresh_expires_at": int(refresh_expires_at.timestamp()),
        }
    ), status


def require_auth(*roles: str) -> Callable:
    def decorator(view: Callable) -> Callable:
        @wraps(view)
        def wrapped(*args, **kwargs):
            header = request.headers.get("Authorization", "")
            if not header.startswith("Bearer ") or not JWT_SECRET:
                audit("access_denied", "failure", details="Missing bearer token")
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
                cursor = conn.cursor()
                cursor.execute("SELECT 1 FROM revoked_access_token WHERE jti = %s", (payload["jti"],))
                revoked = cursor.fetchone() is not None
                cursor.close()
                conn.close()
                if revoked:
                    raise jwt.InvalidTokenError("Access token was revoked")
            except (jwt.PyJWTError, TypeError, ValueError):
                audit("access_denied", "failure", details="Invalid or expired access token")
                return jsonify({"error": "Invalid or expired access token"}), 401
            if roles and g.user_role not in roles:
                audit("access_denied", "failure", user_id=g.user_id, details="Insufficient role")
                return jsonify({"error": "Forbidden"}), 403
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
    if user_type not in VALID_ROLES:
        raise ValueError("user_type must be technician or owner")

    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            "SELECT user_id FROM user WHERE email = %s OR username = %s LIMIT 1",
            (email, name),
        )
        if cursor.fetchone():
            return jsonify({"error": "Unable to create account"}), 409
        code = f"{secrets.randbelow(1_000_000):06d}"
        cursor.execute(
            "DELETE FROM registration_otp WHERE email = %s OR username = %s",
            (email, name),
        )
        cursor.execute(
            """INSERT INTO registration_otp
               (username, email, password_hash, role, code_hash, expires_at)
               VALUES (%s, %s, %s, %s, %s, UTC_TIMESTAMP() + INTERVAL %s MINUTE)""",
            (name, email, password_hasher.hash(password), user_type, token_hash(code), OTP_MINUTES),
        )
        conn.commit()
        if SMTP_HOST and SMTP_USERNAME and SMTP_PASSWORD and SMTP_FROM:
            send_registration_otp(email, code)
        elif not (DEV_MODE and EXPOSE_REGISTRATION_OTP):
            raise RuntimeError("SMTP is not configured")
    except (IntegrityError, smtplib.SMTPException, RuntimeError):
        conn.rollback()
        app.logger.exception("Registration OTP delivery failed")
        return jsonify({"error": "Unable to send verification email"}), 503
    finally:
        cursor.close()
        conn.close()
    response = {"message": "Verification code sent to the supplied email"}
    if DEV_MODE and EXPOSE_REGISTRATION_OTP:
        response["development_code"] = code
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
        """SELECT * FROM registration_otp
           WHERE email = %s AND verified_at IS NULL
             AND expires_at > UTC_TIMESTAMP() AND attempts < 5
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
            "INSERT INTO user (username, email, password, role) VALUES (%s, %s, %s, %s)",
            (pending["username"], pending["email"], pending["password_hash"], pending["role"]),
        )
        user_id = cursor.lastrowid
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
    user = {"user_id": user_id, "username": pending["username"], "email": email, "user_type": pending["role"]}
    audit("registration", "success", user_id=user_id, resource_type="user", resource_id=user_id)
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
        f"""SELECT user_id, username, email, role AS user_type,
                   password AS password_hash, is_active
            FROM user WHERE {login_column} = %s LIMIT 1""",
        (identifier,),
    )
    user = cursor.fetchone()
    cursor.close()
    conn.close()

    valid = False
    if user and user["is_active"]:
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
                  u.user_id AS id, u.username AS name, u.email, u.role AS user_type, u.is_active
           FROM refresh_token rt JOIN user u ON u.user_id = rt.user_id
           WHERE rt.token_hash = %s""",
        (hashed,),
    )
    row = cursor.fetchone()
    if not row or row["revoked_at"] or row["expires_at"] <= datetime.utcnow() or not row["is_active"]:
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
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT user_id AS id FROM user WHERE email = %s AND is_active = TRUE", (email,))
    user = cursor.fetchone()
    reset_token = None
    if user:
        reset_token = secrets.token_urlsafe(32)
        try:
            cursor.execute("UPDATE password_reset_token SET used_at = UTC_TIMESTAMP() WHERE user_id = %s AND used_at IS NULL", (user["id"],))
            cursor.execute(
                "INSERT INTO password_reset_token (user_id, token_hash, expires_at) VALUES (%s, %s, %s)",
                (user["id"], token_hash(reset_token), (utcnow() + timedelta(minutes=RESET_TOKEN_MINUTES)).replace(tzinfo=None)),
            )
            if SMTP_HOST and SMTP_USERNAME and SMTP_PASSWORD and SMTP_FROM:
                send_password_reset_email(email, reset_token)
            elif not EXPOSE_RESET_TOKEN:
                raise RuntimeError("SMTP is not configured")
            conn.commit()
        except (smtplib.SMTPException, OSError, RuntimeError):
            conn.rollback()
            app.logger.exception("Password reset email delivery failed")
            reset_token = None
    cursor.close()
    conn.close()
    audit("password_reset_requested", "success", user_id=user["id"] if user else None)
    response = {"message": "If the account exists, password reset instructions have been sent."}
    if EXPOSE_RESET_TOKEN and reset_token:
        response["reset_token"] = reset_token
    return jsonify(response)


def complete_password_reset(raw_token: str, password: str) -> bool:
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        """SELECT reset_token_id AS id, user_id FROM password_reset_token
           WHERE token_hash = %s AND used_at IS NULL AND expires_at > UTC_TIMESTAMP() FOR UPDATE""",
        (token_hash(raw_token),),
    )
    reset = cursor.fetchone()
    if not reset:
        cursor.close()
        conn.close()
        return False
    cursor.execute("UPDATE user SET password = %s WHERE user_id = %s", (password_hasher.hash(password), reset["user_id"]))
    cursor.execute("UPDATE password_reset_token SET used_at = UTC_TIMESTAMP() WHERE reset_token_id = %s", (reset["id"],))
    cursor.execute("UPDATE refresh_token SET revoked_at = UTC_TIMESTAMP() WHERE user_id = %s AND revoked_at IS NULL", (reset["user_id"],))
    conn.commit()
    cursor.close()
    conn.close()
    audit("password_reset", "success", user_id=reset["user_id"])
    return True


@app.route("/reset-password", methods=["GET", "POST"])
@limiter.limit("5 per hour", exempt_when=lambda: DEV_MODE)
def reset_password_page():
    raw_token = request.values.get("token", "")
    error = None
    can_submit = isinstance(raw_token, str) and 20 <= len(raw_token) <= 200
    if not can_submit:
        error = "This password reset link is invalid or incomplete."
    if request.method == "POST" and error is None:
        password = request.form.get("password", "")
        confirmation = request.form.get("confirmation", "")
        if password != confirmation:
            error = "The passwords do not match."
        else:
            try:
                password = validate_password(password)
            except ValueError as exc:
                error = str(exc)
        if error is None and complete_password_reset(raw_token, password):
            return render_template("reset_password.html", success=True)
        if error is None:
            audit("password_reset", "failure")
            error = "This password reset link is invalid or has expired."
            can_submit = False
    return render_template(
        "reset_password.html",
        token=raw_token,
        error=error,
        success=False,
        can_submit=can_submit,
    ), 400 if error else 200


@app.get("/api/users")
@require_auth("owner")
def get_users():
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT user_id AS id, username AS name, email, role AS user_type, is_active, created_at FROM user ORDER BY created_at DESC")
    rows = cursor.fetchall()
    cursor.close()
    conn.close()
    return jsonify(rows)


@app.get("/api/audio-tests")
@require_auth("technician", "owner")
def get_audio_tests():
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT * FROM audio_tests WHERE user_id = %s ORDER BY created_at DESC", (g.user_id,))
    rows = cursor.fetchall()
    cursor.close()
    conn.close()
    return jsonify(rows)


@app.get("/api/audio-tests/<int:test_id>")
@require_auth("technician", "owner")
def get_audio_test(test_id: int):
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT * FROM audio_tests WHERE id = %s AND user_id = %s", (test_id, g.user_id))
    row = cursor.fetchone()
    cursor.close()
    conn.close()
    return (jsonify(row), 200) if row else (jsonify({"error": "Not found"}), 404)


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
    if status not in VALID_STATUSES:
        raise ValueError("status is invalid")
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        """INSERT INTO audio_tests
           (user_id, test_name, score, noise_level, distortion_level, status, duration_seconds)
           VALUES (%s, %s, %s, %s, %s, %s, %s)""",
        (g.user_id, test_name, score, noise, distortion, status, duration),
    )
    conn.commit()
    test_id = cursor.lastrowid
    cursor.close()
    conn.close()
    audit("audio_test_created", "success", user_id=g.user_id, resource_type="audio_test", resource_id=test_id)
    return jsonify({"id": test_id, "test_name": test_name, "score": score}), 201


@app.delete("/api/audio-tests/<int:test_id>")
@require_auth("technician", "owner")
def delete_audio_test(test_id: int):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM audio_tests WHERE id = %s AND user_id = %s", (test_id, g.user_id))
    deleted = cursor.rowcount
    conn.commit()
    cursor.close()
    conn.close()
    if not deleted:
        return jsonify({"error": "Not found"}), 404
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
        cursor.execute("SELECT * FROM genre_settings WHERE genre = %s ORDER BY updated_at DESC LIMIT 1", (genre,))
        result = cursor.fetchone()
    else:
        cursor.execute("SELECT * FROM genre_settings ORDER BY genre")
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
        """INSERT INTO genre_settings (user_id, genre, volume, bass, treble, flatness, sharpness)
           VALUES (%s, %s, %s, %s, %s, %s, %s)""",
        (g.user_id, genre, *values),
    )
    conn.commit()
    setting_id = cursor.lastrowid
    cursor.close()
    conn.close()
    audit("genre_settings_saved", "success", user_id=g.user_id, resource_type="genre_setting", resource_id=setting_id)
    return jsonify({"id": setting_id, "genre": genre}), 201


@app.get("/api/audio-uploads")
@require_auth("owner")
def get_audio_uploads():
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT * FROM audio_uploads WHERE user_id = %s ORDER BY created_at DESC", (g.user_id,))
    rows = cursor.fetchall()
    cursor.close()
    conn.close()
    return jsonify(rows)


@app.post("/api/audio-uploads")
@require_auth("owner")
def create_audio_upload():
    data = json_body()
    file_name = clean_text(data.get("file_name"), "file_name", 1, 255)
    genre = clean_text(data.get("genre"), "genre", 2, 50) if data.get("genre") else None
    score = int(bounded_number(data.get("score"), "score", 0, 100)) if data.get("score") is not None else None
    status = data.get("status", "Acceptable")
    if status not in VALID_STATUSES:
        raise ValueError("status is invalid")
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        "INSERT INTO audio_uploads (user_id, file_name, genre, score, status) VALUES (%s, %s, %s, %s, %s)",
        (g.user_id, file_name, genre, score, status),
    )
    conn.commit()
    upload_id = cursor.lastrowid
    cursor.close()
    conn.close()
    audit("audio_upload_created", "success", user_id=g.user_id, resource_type="audio_upload", resource_id=upload_id)
    return jsonify({"id": upload_id, "file_name": file_name, "genre": genre}), 201


@app.get("/api/audit-logs")
@require_auth("owner")
def get_audit_logs():
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        """SELECT id, user_id, action, resource_type, resource_id, result, ip_address, created_at
           FROM audit_log ORDER BY created_at DESC LIMIT 200"""
    )
    rows = cursor.fetchall()
    cursor.close()
    conn.close()
    return jsonify(rows)


if __name__ == "__main__":
    if not JWT_SECRET or len(JWT_SECRET) < 32:
        raise RuntimeError("JWT_SECRET must be set to a random value of at least 32 characters")
    app.run(host=os.getenv("APP_HOST", "127.0.0.1"), port=int(os.getenv("APP_PORT", "5000")), debug=os.getenv("FLASK_DEBUG", "false").lower() == "true")
