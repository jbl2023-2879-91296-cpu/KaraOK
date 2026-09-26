"""Accounts implementation."""

from __future__ import annotations

from argon2.exceptions import InvalidHashError
from argon2.exceptions import VerifyMismatchError
from datetime import datetime
from flask import g
from flask import jsonify
from flask import request
from karaok.auth.access import require_auth
from karaok.auth.mail import send_registration_otp
from karaok.auth.mail import send_temporary_password_email
from karaok.auth.tokens import create_refresh_token
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
from karaok.core.config import OTP_MINUTES
from karaok.core.config import SMTP_FROM
from karaok.core.config import SMTP_HOST
from karaok.core.config import SMTP_PASSWORD
from karaok.core.config import SMTP_USERNAME
from karaok.core.database import get_db
from karaok.core.passwords import EMAIL_RE
from karaok.core.passwords import clean_email
from karaok.core.passwords import generate_temporary_password
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
import smtplib


SELF_REGISTER_ROLE = "user"


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
