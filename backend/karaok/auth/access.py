"""Access implementation."""

from __future__ import annotations

from flask import g
from flask import jsonify
from flask import request
from functools import wraps
from karaok.auth.tokens import _token_precedes_security_update
from karaok.core.audit import audit
from karaok.core.config import JWT_ISSUER
from karaok.core.config import JWT_SECRET
from karaok.core.database import get_db
from karaok.core.runtime import app
from typing import Callable
import jwt


def require_auth(*roles: str) -> Callable:
    def decorator(view: Callable) -> Callable:
        @wraps(view)
        def wrapped(*args, **kwargs):
            header = request.headers.get("Authorization", "")
            if not header.startswith("Bearer ") or not JWT_SECRET:
                reason = (
                    "Missing bearer token"
                    if not header.startswith("Bearer ")
                    else "JWT secret is not configured"
                )
                app.logger.warning("Access token rejected: %s", reason)
                audit("access_denied", "failure", details=reason)
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
                cursor = conn.cursor(dictionary=True)
                cursor.execute("SELECT 1 FROM revoked_access_token WHERE jti = %s", (payload["jti"],))
                revoked = cursor.fetchone() is not None
                cursor.execute(
                    """SELECT role, is_active, email_verified_at,
                              UNIX_TIMESTAMP(security_updated_at)
                                  AS security_updated_at_epoch,
                              requires_password_change
                       FROM user WHERE user_id = %s""",
                    (g.user_id,),
                )
                account = cursor.fetchone()
                cursor.close()
                conn.close()
                if revoked:
                    raise jwt.InvalidTokenError("Access token was revoked")
                if (
                    not account
                    or not account["is_active"]
                    or account["email_verified_at"] is None
                    or account["role"] != g.user_role
                    or _token_precedes_security_update(payload, account)
                ):
                    raise jwt.InvalidTokenError("Account security state changed")
            except (jwt.PyJWTError, TypeError, ValueError) as error:
                reason = str(error).strip() or type(error).__name__
                app.logger.warning("Access token rejected: %s", reason)
                audit(
                    "access_denied",
                    "failure",
                    details=f"Invalid or expired access token: {reason}",
                )
                return jsonify({"error": "Invalid or expired access token"}), 401
            g.authenticated_user_id = g.user_id
            if roles and g.user_role not in roles:
                audit("access_denied", "failure", user_id=g.user_id, details="Insufficient role")
                return jsonify({"error": "Forbidden"}), 403
            g.requires_password_change = bool(account["requires_password_change"])
            if g.requires_password_change and not (
                request.endpoint or ""
            ).endswith("change_password"):
                audit(
                    "access_denied",
                    "failure",
                    user_id=g.user_id,
                    details="Password change required",
                )
                return jsonify({"error": "Password change required"}), 403
            return view(*args, **kwargs)

        return wrapped

    return decorator
