"""Accounts implementation."""

from __future__ import annotations

from argon2.exceptions import InvalidHashError
from argon2.exceptions import VerifyMismatchError
from contextlib import contextmanager
from datetime import datetime, timezone
from functools import wraps
from flask import g
from flask import jsonify
from flask import request
from karaok.auth.access import require_auth
from karaok.auth.mail import send_registration_otp
from karaok.auth.mail import send_account_exists_notice, send_password_changed_notice, send_reset_otp
from karaok.auth.mail_queue import MailReservation, enqueue_mail
from karaok.auth.otp import (
    ResendTooSoon, challenge_payload, decoy_challenge, issue_challenge,
    resend_challenge, verify_challenge,
)
from karaok.auth.tokens import create_refresh_token, insert_refresh_token
from karaok.auth.tokens import issue_access_token
from karaok.core.accounts import _clean_birthday
from karaok.core.accounts import _clean_phone
from karaok.core.accounts import _clean_profile_image
from karaok.core.accounts import _profile_response
from karaok.core.audit import audit
from karaok.core.config import DEV_MODE
from karaok.core.config import EXPOSE_REGISTRATION_OTP
from karaok.core.config import JWT_ISSUER
from karaok.core.config import JWT_SECRET
from karaok.core.config import SMTP_FROM
from karaok.core.config import SMTP_HOST
from karaok.core.config import SMTP_PASSWORD
from karaok.core.config import SMTP_USERNAME
import karaok.core.config as config
from karaok.core.database import get_db
from karaok.core.email_policy import canonical_email, clean_registration_email
from karaok.core.request_context import client_ip
from karaok.security.throttle import (
    ThrottleDecision, auth_throttle, request_device_id, throttled_response,
)
from karaok.core.passwords import EMAIL_RE
from karaok.core.passwords import clean_email
from karaok.core.passwords import password_hasher
from karaok.core.passwords import token_hash
from karaok.core.passwords import validate_password
from karaok.core.runtime import app
from karaok.core.runtime import limiter
from karaok.core.validation import clean_text
from karaok.core.validation import json_body
from mysql.connector import IntegrityError
from typing import Any
import jwt
import re
import secrets


SELF_REGISTER_ROLE = "user"
SIGNUP_ACCEPTED = "If this email can be registered, a verification code has been sent."
RESET_ACCEPTED = "If an account exists for this email, a reset code has been sent."
AUTH_FLOOD_LIMIT = f"{config.AUTH_IP_CEILING_PER_MINUTE} per minute"


def _request_throttle(action, email=None):
    decision = auth_throttle.check(action, email=email, device_id=request_device_id(), ip=client_ip())
    return None if decision.allowed else throttled_response(decision)


@contextmanager
def _transaction():
    connection = get_db()
    try:
        cursor = connection.cursor(dictionary=True)
        try:
            yield cursor
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            cursor.close()
    finally:
        connection.close()


def _otp_response(purpose, email, challenge):
    registration = purpose == "registration"
    response = challenge_payload(challenge)
    response["message"] = SIGNUP_ACCEPTED if registration else RESET_ACCEPTED
    if registration:
        response["email"] = email
    if registration and DEV_MODE and EXPOSE_REGISTRATION_OTP:
        response["development_code"] = challenge.code or f"{secrets.randbelow(1_000_000):06d}"
    return jsonify(response), 202


def _mail_unavailable():
    g.karaok_retry_after = 30
    return (
        jsonify(error="We could not send the code right now. Try again shortly.", retry_after=30),
        503,
        {"Retry-After": "30"},
    )


def _mail_available():
    return all((SMTP_HOST, SMTP_USERNAME, SMTP_PASSWORD, SMTP_FROM))


def _submit_otp_mail(reservation, purpose, email, challenge, existing_email=None):
    if challenge.code and _mail_available():
        send = send_registration_otp if purpose == "registration" else send_reset_otp
        return reservation.submit(lambda: send(email, challenge.code), description=purpose)
    if existing_email and _mail_available():
        return reservation.submit(
            lambda: send_account_exists_notice(existing_email), description="existing account notice"
        )
    return True


def _select_user(cursor, email, purpose, *, include_profile=False):
    if purpose == "registration":
        condition = "email_verified_at IS NULL AND role = 'user'"
    else:
        condition = "email_verified_at IS NOT NULL AND is_active = TRUE"
    fields = "user.*, role AS user_type" if include_profile else "user_id, password"
    cursor.execute(f"SELECT {fields} FROM user WHERE email = %s AND {condition} FOR UPDATE", (email,))
    return cursor.fetchone()


def _challenge_form():
    data = json_body()
    email = clean_email(data.get("email"))
    challenge_id = data.get("challenge_id")
    if not isinstance(challenge_id, str) or not re.fullmatch(r"[0-9a-f]{32}", challenge_id):
        challenge_id = None
    return data, email, challenge_id


def _new_username(cursor):
    while True:
        username = "user_" + secrets.token_hex(16)
        cursor.execute("SELECT user_id FROM user WHERE username = %s LIMIT 1", (username,))
        if cursor.fetchone() is None:
            return username


def _valid_code(code):
    return isinstance(code, str) and re.fullmatch(r"[0-9]{6}", code)


def _invalid_code(purpose):
    label = "verification" if purpose == "registration" else "reset"
    message = f"Invalid or expired {label} code"
    return _auth_error(message, 400, code=message)


def _auth_error(message, status=400, **fields):
    payload = {"error": message}
    if len(fields) == 1:
        payload["field"] = next(iter(fields))
    elif fields:
        payload["errors"] = fields
    return jsonify(payload), status


def _field_errors(view):
    """Add form field keys without changing legacy error messages."""
    @wraps(view)
    def wrapped(*args, **kwargs):
        try:
            return view(*args, **kwargs)
        except ValueError as error:
            message = str(error)
            field = message.split(" ", 1)[0]
            field = {"verification": "code", "current": "current_password",
                     "new": "new_password", "public": "user_type",
                     "profile": "profile_image"}.get(field, field)
            if field == "username" and view.__name__ == "login":
                field = "identifier"
            if field == "password" and view.__name__ == "change_password":
                field = "new_password"
            if field not in {"email", "username", "identifier", "password", "code",
                             "current_password", "new_password", "user_type",
                             "first_name", "last_name", "address", "city",
                             "state_province", "area_code", "country", "country_code",
                             "phone_number", "birthday", "profile_image",
                             "profile_image_base64", "profile_image_mime"}:
                field = "form"
            return _auth_error(message, **{field: message})
    return wrapped


def auth_response(user: dict[str, Any], status: int = 200, *, cursor=None):
    access_token, access_expires_at = issue_access_token(user)
    refresh_token, refresh_expires_at = (
        create_refresh_token(user["user_id"]) if cursor is None
        else insert_refresh_token(cursor, user["user_id"])
    )
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


@_field_errors
@limiter.limit(AUTH_FLOOD_LIMIT)
def register():
    data = json_body()
    username = (clean_text(data["username"], "username", 3, 50)
                if data.get("username") is not None else None)
    if username is not None and not re.fullmatch(r"[A-Za-z0-9_.-]{3,50}", username):
        raise ValueError(
            "username may contain only letters, numbers, dots, dashes, and underscores"
        )
    # Older clients may still send profile details. Validate supplied values,
    # but keep deferred information genuinely absent in storage.
    def optional_text(field, minimum, maximum):
        value = data.get(field)
        return None if value is None else clean_text(value, field, minimum, maximum)

    first_name = optional_text("first_name", 1, 80)
    last_name = optional_text("last_name", 1, 80)
    try:
        email = clean_registration_email(data.get("email"))
    except ValueError as error:
        if str(error) != "email domain is not supported":
            raise
        message = "Use an email from a supported provider such as Gmail, Yahoo, Outlook or iCloud."
        return _auth_error(message, email=message)
    password = validate_password(data.get("password"))
    address = optional_text("address", 5, 255)
    city = optional_text("city", 2, 100)
    state_province = optional_text("state_province", 2, 100)
    area_code = optional_text("area_code", 2, 20)
    country = optional_text("country", 2, 80)
    country_code = optional_text("country_code", 2, 2)
    if country_code is not None:
        country_code = country_code.upper()
        if not re.fullmatch(r"[A-Z]{2}", country_code):
            raise ValueError("country_code must be a two-letter ISO country code")
    phone_number = (
        _clean_phone(data["phone_number"]) if data.get("phone_number") is not None else None
    )
    birthday = _clean_birthday(data["birthday"]) if data.get("birthday") is not None else None
    profile_image, profile_image_mime = _clean_profile_image(data)
    if "user_type" in data and data.get("user_type") != SELF_REGISTER_ROLE:
        raise ValueError("public registration creates user accounts only")

    canonical = canonical_email(email)
    blocked = _request_throttle("register", canonical)
    if blocked:
        return blocked
    with MailReservation() as reservation:
        if not reservation.available or not (_mail_available() or (DEV_MODE and EXPOSE_REGISTRATION_OTP)):
            return _mail_unavailable()
        decision = auth_throttle.reserve_otp_send("registration", canonical)
        if not decision.allowed:
            return throttled_response(decision)
        decision = auth_throttle.reserve_otp_sender(device_id=request_device_id(), ip=client_ip())
        if not decision.allowed:
            return throttled_response(decision)
        password_hash = password_hasher.hash(password)
        existing_email = None
        try:
            with _transaction() as cursor:
                cursor.execute(
                    """SELECT user_id, username, email, email_verified_at, role FROM user
                       WHERE email_canonical = %s OR email = %s
                       ORDER BY email_verified_at IS NULL, email <> %s, user_id FOR UPDATE""",
                    (canonical, email, email),
                )
                candidate = cursor.fetchone()
                # This query can find multiple historical aliases.
                cursor.fetchall()
                if candidate and (candidate["email"] != email or candidate["email_verified_at"]
                                  or candidate["role"] != SELF_REGISTER_ROLE
                                  or username not in (None, candidate["username"])):
                    if candidate["email_verified_at"]:
                        existing_email = candidate["email"]
                    challenge = decoy_challenge()
                else:
                    username = username or (candidate["username"] if candidate else _new_username(cursor))
                    profile = (first_name, last_name, password_hash, address, city, state_province,
                               area_code, country, country_code, phone_number, birthday,
                               profile_image, profile_image_mime)
                    if candidate:
                        user_id = candidate["user_id"]
                        cursor.execute(
                            """UPDATE user SET email_canonical=%s, first_name=%s, last_name=%s,
                               password=%s, address=%s, city=%s, state_province=%s, area_code=%s,
                               country=%s, country_code=%s, phone_number=%s, birthday=%s,
                               profile_image=%s, profile_image_mime=%s WHERE user_id=%s""",
                            (canonical, *profile, user_id),
                        )
                    else:
                        cursor.execute(
                            """INSERT INTO user (username, email, email_canonical, first_name,
                               last_name, password, address, city, state_province, area_code,
                               country, country_code, phone_number, birthday, profile_image,
                               profile_image_mime, role, email_verified_at)
                               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'user',NULL)""",
                            (username, email, canonical, *profile),
                        )
                        user_id = cursor.lastrowid
                    challenge = issue_challenge(cursor, purpose="registration", user_id=user_id, email=email)
        except IntegrityError:
            # A concurrent insert or an older client's taken username uses the same response.
            challenge = decoy_challenge()
        except ResendTooSoon as error:
            return throttled_response(ThrottleDecision(False, error.retry_after))
        if not _submit_otp_mail(reservation, "registration", email, challenge, existing_email):
            return _mail_unavailable()
    return _otp_response("registration", email, challenge)


@_field_errors
@limiter.limit(AUTH_FLOOD_LIMIT)
def verify_registration():
    data, email, challenge_id = _challenge_form()
    blocked = _request_throttle("register_verify", canonical_email(email))
    if blocked:
        return blocked
    code = data.get("code")
    if not challenge_id or not _valid_code(code):
        return _invalid_code("registration")
    with _transaction() as cursor:
        user = _select_user(cursor, email, "registration", include_profile=True)
        if not user or not verify_challenge(
            cursor, purpose="registration", challenge_id=challenge_id, email=email, code=code,
        ):
            return _invalid_code("registration")
        cursor.execute("UPDATE user SET email_verified_at = UTC_TIMESTAMP() WHERE user_id = %s", (user["user_id"],))
        response = auth_response(user, 201, cursor=cursor)
    audit("registration", "success", user_id=user["user_id"], resource_type="user", resource_id=user["user_id"])
    return response


def _request_otp(purpose, action, *, resend=False):
    _, email, challenge_id = _challenge_form()
    canonical = canonical_email(email)
    blocked = _request_throttle(action, canonical)
    if blocked:
        return blocked
    if resend and not challenge_id:
        return _invalid_code(purpose)
    if not resend:
        challenge_id = None
    with MailReservation() as reservation:
        if not reservation.available or not (_mail_available() or (DEV_MODE and EXPOSE_REGISTRATION_OTP)):
            return _mail_unavailable()
        decision = auth_throttle.reserve_otp_send(purpose, canonical if purpose == "registration" else email)
        if not decision.allowed:
            return throttled_response(decision)
        decision = auth_throttle.reserve_otp_sender(device_id=request_device_id(), ip=client_ip())
        if not decision.allowed:
            return throttled_response(decision)
        try:
            with _transaction() as cursor:
                user = _select_user(cursor, email, purpose)
                if not user:
                    challenge = decoy_challenge(challenge_id)
                elif resend:
                    challenge = resend_challenge(
                        cursor, purpose=purpose, user_id=user["user_id"], email=email, challenge_id=challenge_id,
                    )
                else:
                    challenge = issue_challenge(cursor, purpose=purpose, user_id=user["user_id"], email=email)
        except ResendTooSoon as error:
            return throttled_response(ThrottleDecision(False, error.retry_after))
        if not _submit_otp_mail(reservation, purpose, email, challenge):
            return _mail_unavailable()
    if purpose == "password_reset" and not resend:
        audit("password_reset_requested", "success", user_id=user["user_id"] if user else None)
    return _otp_response(purpose, email, challenge)


@_field_errors
@limiter.limit(AUTH_FLOOD_LIMIT)
def resend_registration():
    return _request_otp("registration", "register_resend", resend=True)


@_field_errors
@limiter.limit(AUTH_FLOOD_LIMIT)
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
    if not isinstance(password, str) or not password or len(password) > 128:
        raise ValueError("password is invalid")

    throttle_identity = canonical_email(identifier) if is_email else identifier.lower()
    blocked = _request_throttle("login", throttle_identity)
    if blocked:
        return blocked

    with _transaction() as cursor:
        cursor.execute(
            f"""SELECT u.user_id, u.username, u.first_name, u.last_name, u.email,
                       u.address, u.city, u.state_province, u.area_code,
                       u.country, u.country_code, u.phone_number,
                       u.birthday, u.profile_image, u.profile_image_mime,
                       u.role AS user_type,
                       u.password AS password_hash, u.is_active, u.email_verified_at,
                       u.requires_password_change
                FROM user u
                WHERE u.{"email" if is_email else "username"} = %s LIMIT 1 FOR UPDATE""",
            (identifier,),
        )
        user = cursor.fetchone()

        valid = False
        if user and user["is_active"] and user["email_verified_at"] is not None:
            try:
                valid = password_hasher.verify(user["password_hash"], password)
            except (VerifyMismatchError, InvalidHashError):
                valid = False
        if valid:
            if password_hasher.check_needs_rehash(user["password_hash"]):
                cursor.execute(
                    "UPDATE user SET password = %s WHERE user_id = %s",
                    (password_hasher.hash(password), user["user_id"]),
                )
            response = auth_response(user, cursor=cursor)
    if not valid:
        audit("login", "failure", user_id=user["user_id"] if user else None)
        decision = auth_throttle.check(
            "login_fail_account", email=throttle_identity, device_id=None, ip="*",
            burst_limit=config.LOGIN_ACCOUNT_FAIL_LIMIT,
            burst_window=config.LOGIN_ACCOUNT_FAIL_WINDOW_SECONDS,
            fixed_lock_seconds=config.AUTH_LOCKOUT_REPEAT_SECONDS,
        )
        if not decision.allowed:
            return throttled_response(decision)
        return _auth_error("Invalid email or password", 401, identifier="Invalid email or password", password="Invalid email or password")
    audit("login", "success", user_id=user["user_id"])
    return response


@limiter.limit(AUTH_FLOOD_LIMIT)
def refresh():
    blocked = _request_throttle("refresh")
    if blocked:
        return blocked
    raw_token = json_body().get("refresh_token")
    if not isinstance(raw_token, str) or len(raw_token) > 200:
        return jsonify({"error": "Invalid refresh token"}), 401
    hashed = token_hash(raw_token)
    with _transaction() as cursor:
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
            or row["expires_at"] <= datetime.now(timezone.utc).replace(tzinfo=None)
            or not row["is_active"]
            or row["email_verified_at"] is None
        ):
            response = None
        else:
            cursor.execute(
                "UPDATE refresh_token SET revoked_at = UTC_TIMESTAMP() WHERE refresh_token_id = %s",
                (row["token_id"],),
            )
            response = auth_response(row, cursor=cursor)
    if response is None:
        audit("token_refresh", "failure")
        return jsonify({"error": "Invalid or expired refresh token"}), 401
    audit("token_refresh", "success", user_id=row["user_id"])
    return response


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


@_field_errors
@limiter.limit(AUTH_FLOOD_LIMIT)
def forgot_password():
    return _request_otp("password_reset", "forgot")


@_field_errors
@limiter.limit(AUTH_FLOOD_LIMIT)
def resend_password_reset():
    return _request_otp("password_reset", "forgot_resend", resend=True)


@_field_errors
@limiter.limit(AUTH_FLOOD_LIMIT)
def reset_password():
    data, email, challenge_id = _challenge_form()
    blocked = _request_throttle("forgot_reset", email)
    if blocked:
        return blocked
    try:
        password = validate_password(data.get("new_password"))
    except ValueError as error:
        return _auth_error(str(error), new_password=str(error))
    code = data.get("code")
    if not challenge_id or not _valid_code(code):
        return _invalid_code("password_reset")
    password_hash = password_hasher.hash(password)
    try:
        with _transaction() as cursor:
            user = _select_user(cursor, email, "password_reset")
            if not user or not verify_challenge(
                cursor, purpose="password_reset", challenge_id=challenge_id, email=email, code=code,
            ):
                return _invalid_code("password_reset")
            try:
                if password_hasher.verify(user["password"], password):
                    raise ValueError("Choose a password you have not used for this account.")
            except (VerifyMismatchError, InvalidHashError):
                pass
            cursor.execute(
                """UPDATE user SET password = %s, requires_password_change = FALSE,
                       security_updated_at = CURRENT_TIMESTAMP(6) WHERE user_id = %s""",
                (password_hash, user["user_id"]),
            )
            cursor.execute(
                """UPDATE refresh_token SET revoked_at = UTC_TIMESTAMP()
                   WHERE user_id = %s AND revoked_at IS NULL""",
                (user["user_id"],),
            )
    except ValueError as error:
        return _auth_error(str(error), new_password=str(error))
    enqueue_mail(lambda: send_password_changed_notice(email), description="password changed notice")
    audit("password_reset_completed", "success", user_id=user["user_id"])
    return jsonify(message="Password updated. Sign in with your new password.")


@_field_errors
@limiter.limit("10 per hour", exempt_when=lambda: DEV_MODE)
@require_auth("user", "admin")
def change_password():
    data = json_body()
    current_password = data.get("current_password")
    new_password = validate_password(data.get("new_password"))
    if not g.requires_password_change and (
        not isinstance(current_password, str) or not current_password or len(current_password) > 128
    ):
        raise ValueError("current password is invalid")
    if current_password == new_password:
        raise ValueError("new password must be different from the current password")

    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT password FROM user WHERE user_id = %s AND is_active = TRUE", (g.user_id,))
    user = cursor.fetchone()
    if not user:
        cursor.close()
        conn.close()
        return _auth_error("Account is unavailable", 401, form="Account is unavailable")
    if g.requires_password_change:
        try:
            if password_hasher.verify(user["password"], new_password):
                cursor.close()
                conn.close()
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
            return _auth_error("Current password is incorrect", 401, current_password="Current password is incorrect")

    cursor.execute(
        """UPDATE user
           SET password = %s, requires_password_change = FALSE, security_updated_at = CURRENT_TIMESTAMP(6)
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
