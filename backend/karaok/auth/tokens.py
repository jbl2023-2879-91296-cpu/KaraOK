"""Tokens implementation."""

from __future__ import annotations

from datetime import datetime
from datetime import timedelta
from flask import request
from karaok.core.config import ACCESS_TOKEN_MINUTES
from karaok.core.config import JWT_ISSUER
from karaok.core.config import JWT_SECRET
from karaok.core.config import REFRESH_TOKEN_DAYS
from karaok.core.database import get_db
from karaok.core.passwords import token_hash
from karaok.core.request_context import client_ip
from karaok.core.time import utcnow
from karaok.security.token_service import issue_access_token as create_access_token
from karaok.security.token_service import token_precedes_security_update
from typing import Any
import secrets


def issue_access_token(user: dict[str, Any]) -> tuple[str, int]:
    return create_access_token(
        user,
        secret=JWT_SECRET,
        issuer=JWT_ISSUER,
        lifetime_minutes=ACCESS_TOKEN_MINUTES,
    )


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


def _token_precedes_security_update(
    payload: dict[str, Any],
    account: dict[str, Any],
) -> bool:
    return token_precedes_security_update(payload, account)
