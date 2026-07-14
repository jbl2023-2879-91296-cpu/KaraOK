from __future__ import annotations

from datetime import datetime, timedelta, timezone
from functools import wraps
import hashlib
import os
import re
import secrets
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
from mysql.connector import Error, IntegrityError


load_dotenv()

app = Flask(__name__)
allowed_origins = [
    origin.strip()
    for origin in os.getenv("CORS_ORIGINS", "http://localhost:*").split(",")
    if origin.strip()
]
CORS(app, resources={r"/api/*": {"origins": allowed_origins}})
limiter = Limiter(get_remote_address, app=app, default_limits=["200 per hour"])

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
            """INSERT INTO audit_logs
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
        "sub": str(user["id"]),
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
        """INSERT INTO refresh_tokens
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
    refresh_token, refresh_expires_at = create_refresh_token(user["id"])
    return jsonify(
        {
            "user": {
                "id": user["id"],
                "name": user["name"],
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
                cursor.execute("SELECT 1 FROM revoked_access_tokens WHERE jti = %s", (payload["jti"],))
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
    name = clean_text(data.get("name"), "name", 2, 100)
    email = clean_email(data.get("email"))
    password = validate_password(data.get("password"))
    user_type = data.get("user_type")
    if user_type not in VALID_ROLES:
        raise ValueError("user_type must be technician or owner")

    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            "INSERT INTO users (name, email, password_hash, user_type) VALUES (%s, %s, %s, %s)",
            (name, email, password_hasher.hash(password), user_type),
        )
        conn.commit()
        user_id = cursor.lastrowid
    except IntegrityError:
        conn.rollback()
        audit("registration", "failure", details="Duplicate email")
        return jsonify({"error": "Unable to create account"}), 409
    finally:
        cursor.close()
        conn.close()

    user = {"id": user_id, "name": name, "email": email, "user_type": user_type}
    audit("registration", "success", user_id=user_id, resource_type="user", resource_id=user_id)
    return auth_response(user, 201)


@app.post("/api/auth/login")
@limiter.limit("5 per minute")
def login():
    data = json_body()
    email = clean_email(data.get("email"))
    password = data.get("password")
    if not isinstance(password, str) or len(password) > 128:
        raise ValueError("password is invalid")

    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        "SELECT id, name, email, user_type, password_hash, is_active FROM users WHERE email = %s",
        (email,),
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
        audit("login", "failure", user_id=user["id"] if user else None)
        return jsonify({"error": "Invalid email or password"}), 401
    if password_hasher.check_needs_rehash(user["password_hash"]):
        conn = get_db()
        cursor = conn.cursor()
        cursor.execute("UPDATE users SET password_hash = %s WHERE id = %s", (password_hasher.hash(password), user["id"]))
        conn.commit()
        cursor.close()
        conn.close()
    audit("login", "success", user_id=user["id"])
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
        """SELECT rt.id AS token_id, rt.user_id, rt.expires_at, rt.revoked_at,
                  u.id, u.name, u.email, u.user_type, u.is_active
           FROM refresh_tokens rt JOIN users u ON u.id = rt.user_id
           WHERE rt.token_hash = %s""",
        (hashed,),
    )
    row = cursor.fetchone()
    if not row or row["revoked_at"] or row["expires_at"] <= datetime.utcnow() or not row["is_active"]:
        cursor.close()
        conn.close()
        audit("token_refresh", "failure")
        return jsonify({"error": "Invalid or expired refresh token"}), 401
    cursor.execute("UPDATE refresh_tokens SET revoked_at = UTC_TIMESTAMP() WHERE id = %s", (row["token_id"],))
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
            "UPDATE refresh_tokens SET revoked_at = UTC_TIMESTAMP() WHERE token_hash = %s AND revoked_at IS NULL",
            (token_hash(raw_token),),
        )
        if access_payload:
            cursor.execute(
                """INSERT IGNORE INTO revoked_access_tokens (jti, user_id, expires_at)
                   VALUES (%s, %s, FROM_UNIXTIME(%s))""",
                (access_payload["jti"], int(access_payload["sub"]), int(access_payload["exp"])),
            )
        conn.commit()
        cursor.close()
        conn.close()
        audit("logout", "success", user_id=int(access_payload["sub"]) if access_payload else None)
    return jsonify({"message": "Logged out"})


@app.post("/api/auth/forgot-password")
@limiter.limit("3 per hour")
def forgot_password():
    email = clean_email(json_body().get("email"))
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT id FROM users WHERE email = %s AND is_active = TRUE", (email,))
    user = cursor.fetchone()
    reset_token = None
    if user:
        reset_token = secrets.token_urlsafe(32)
        cursor.execute("UPDATE password_reset_tokens SET used_at = UTC_TIMESTAMP() WHERE user_id = %s AND used_at IS NULL", (user["id"],))
        cursor.execute(
            "INSERT INTO password_reset_tokens (user_id, token_hash, expires_at) VALUES (%s, %s, %s)",
            (user["id"], token_hash(reset_token), (utcnow() + timedelta(minutes=RESET_TOKEN_MINUTES)).replace(tzinfo=None)),
        )
        conn.commit()
    cursor.close()
    conn.close()
    audit("password_reset_requested", "success", user_id=user["id"] if user else None)
    response = {"message": "If the account exists, password reset instructions have been created."}
    if EXPOSE_RESET_TOKEN and reset_token:
        response["reset_token"] = reset_token
    return jsonify(response)


@app.post("/api/auth/reset-password")
@limiter.limit("5 per hour")
def reset_password():
    data = json_body()
    raw_token = data.get("token")
    password = validate_password(data.get("password"))
    if not isinstance(raw_token, str):
        raise ValueError("token is required")
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        """SELECT id, user_id FROM password_reset_tokens
           WHERE token_hash = %s AND used_at IS NULL AND expires_at > UTC_TIMESTAMP() FOR UPDATE""",
        (token_hash(raw_token),),
    )
    reset = cursor.fetchone()
    if not reset:
        cursor.close()
        conn.close()
        audit("password_reset", "failure")
        return jsonify({"error": "Invalid or expired reset token"}), 400
    cursor.execute("UPDATE users SET password_hash = %s WHERE id = %s", (password_hasher.hash(password), reset["user_id"]))
    cursor.execute("UPDATE password_reset_tokens SET used_at = UTC_TIMESTAMP() WHERE id = %s", (reset["id"],))
    cursor.execute("UPDATE refresh_tokens SET revoked_at = UTC_TIMESTAMP() WHERE user_id = %s AND revoked_at IS NULL", (reset["user_id"],))
    conn.commit()
    cursor.close()
    conn.close()
    audit("password_reset", "success", user_id=reset["user_id"])
    return jsonify({"message": "Password reset successful. Please log in."})


@app.get("/api/users")
@require_auth("owner")
def get_users():
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT id, name, email, user_type, is_active, created_at FROM users ORDER BY created_at DESC")
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
           FROM audit_logs ORDER BY created_at DESC LIMIT 200"""
    )
    rows = cursor.fetchall()
    cursor.close()
    conn.close()
    return jsonify(rows)


if __name__ == "__main__":
    if not JWT_SECRET or len(JWT_SECRET) < 32:
        raise RuntimeError("JWT_SECRET must be set to a random value of at least 32 characters")
    app.run(host=os.getenv("APP_HOST", "127.0.0.1"), port=int(os.getenv("APP_PORT", "5000")), debug=os.getenv("FLASK_DEBUG", "false").lower() == "true")
