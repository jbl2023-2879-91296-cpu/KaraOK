"""Users implementation."""

from __future__ import annotations

from flask import jsonify
from karaok.auth.access import require_auth
from karaok.core.database import get_db


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
