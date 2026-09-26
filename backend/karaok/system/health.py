"""Health implementation."""

from __future__ import annotations

from flask import jsonify
from karaok.core.database import get_db
from mysql.connector import Error


def health():
    try:
        conn = get_db()
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        cursor.fetchone()
        cursor.close()
        conn.close()
        return jsonify({"status": "ok", "db": "connected"})
    except Error:
        return jsonify({"status": "error", "db": "unavailable"}), 503
