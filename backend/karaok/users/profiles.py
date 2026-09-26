"""Profiles implementation."""

from __future__ import annotations

from flask import g
from flask import jsonify
from karaok.auth.access import require_auth
from karaok.core.accounts import _clean_birthday
from karaok.core.accounts import _clean_phone
from karaok.core.accounts import _clean_profile_image
from karaok.core.accounts import _profile_response
from karaok.core.audit import audit
from karaok.core.database import get_db
from karaok.core.validation import clean_text
from karaok.core.validation import json_body
from mysql.connector import IntegrityError
from typing import Any
import re


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
