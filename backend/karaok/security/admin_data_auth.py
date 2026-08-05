"""Authentication for the machine-to-machine Data Administration API."""

from __future__ import annotations

from functools import wraps
import hashlib
import hmac

from flask import g, jsonify, request

from ..config import ADMIN_DATA_API_ENABLED, ADMIN_DATA_API_KEY_HASH


def require_admin_data_key(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        header = request.headers.get("Authorization", "")
        supplied = header[7:] if header.startswith("Bearer ") else ""
        supplied_hash = hashlib.sha256(supplied.encode("utf-8")).hexdigest()
        configured = (
            ADMIN_DATA_API_ENABLED
            and len(ADMIN_DATA_API_KEY_HASH) == 64
            and all(character in "0123456789abcdef" for character in ADMIN_DATA_API_KEY_HASH)
        )
        if not configured or len(supplied) < 32 or not hmac.compare_digest(
            supplied_hash, ADMIN_DATA_API_KEY_HASH
        ):
            return jsonify({"error": "Data administration authentication required"}), 401
        g.authenticated_admin_actor = request.headers.get(
            "X-KaraOK-Admin-Actor", "local-admin"
        )[:64]
        return view(*args, **kwargs)

    return wrapped
