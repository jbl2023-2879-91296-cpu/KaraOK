"""Stateless JWT creation and security-version comparison."""

from datetime import datetime, timedelta, timezone
import secrets
from typing import Any

import jwt


def issue_access_token(
    user: dict[str, Any],
    *,
    secret: str,
    issuer: str,
    lifetime_minutes: int,
) -> tuple[str, int]:
    now = datetime.now(timezone.utc)
    expires = now + timedelta(minutes=lifetime_minutes)
    payload = {
        "sub": str(user["user_id"]),
        "role": user["user_type"],
        "iss": issuer,
        "iat": now,
        "nbf": now,
        "exp": expires,
        "jti": secrets.token_hex(16),
    }
    return jwt.encode(payload, secret, algorithm="HS256"), int(expires.timestamp())


def token_precedes_security_update(
    payload: dict[str, Any],
    account: dict[str, Any],
) -> bool:
    updated_epoch = account.get("security_updated_at_epoch")
    if updated_epoch is None:
        return False
    return int(payload["iat"]) < int(updated_epoch)
