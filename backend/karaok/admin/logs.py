"""Logs implementation."""

from __future__ import annotations

from flask import jsonify
from karaok.auth.access import require_auth
from karaok.core.database import get_db


@require_auth("admin")
def get_audit_logs():
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        """SELECT audit_log_id AS id, user_id, action, resource_type, resource_id, result, ip_address, created_at
           FROM audit_log ORDER BY created_at DESC LIMIT 200"""
    )
    rows = cursor.fetchall()
    cursor.close()
    conn.close()
    return jsonify(rows)


@require_auth("admin")
def get_request_logs():
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        """SELECT request_log_id AS id, user_id, method, path, endpoint,
                  status_code, duration_ms, ip_address, user_agent, created_at
           FROM api_request_log
           ORDER BY created_at DESC, request_log_id DESC
           LIMIT 200"""
    )
    rows = cursor.fetchall()
    cursor.close()
    conn.close()
    return jsonify(rows)
