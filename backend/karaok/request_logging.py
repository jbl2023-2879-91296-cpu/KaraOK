"""Request logging implementation."""

from __future__ import annotations

from flask import g
from flask import request
from karaok.core.request_context import client_ip
from karaok.core.runtime import app
from karaok.core.database import get_db
import time


def begin_api_request_log() -> None:
    if (
        not app.config.get("TESTING", False)
        and request.path.startswith("/api/")
        and request.method != "OPTIONS"
    ):
        g.api_request_started = time.monotonic()


def complete_api_request_log(response):
    started = getattr(g, "api_request_started", None)
    if started is None:
        return response
    duration_ms = round((time.monotonic() - started) * 1000.0, 3)
    conn = None
    cursor = None
    try:
        conn = get_db()
        cursor = conn.cursor()
        cursor.execute(
            """INSERT INTO api_request_log
               (user_id, method, path, endpoint, status_code, duration_ms,
                ip_address, user_agent)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
            (
                getattr(g, "authenticated_user_id", None),
                request.method[:10],
                request.path[:255],
                (request.endpoint or "").rsplit(".", 1)[-1][:100] or None,
                response.status_code,
                duration_ms,
                client_ip(),
                request.headers.get("User-Agent", "")[:255],
            ),
        )
        conn.commit()
    except Exception:
        app.logger.exception("Could not write API request log")
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None and conn.is_connected():
            conn.close()
    return response
