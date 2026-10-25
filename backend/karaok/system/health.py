"""Health implementation."""

from __future__ import annotations

from flask import current_app, jsonify
from karaok.core.database import get_db
from mysql.connector import Error


# Columns used by every recommendation read must exist before backend deployment.
REQUIRED_COLUMNS = (
    ("settings_recommendation", "feedback"),
    ("audio_analysis_result", "noise_reliable"),
)


def health():
    conn = None
    cursor = None
    try:
        conn = get_db()
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        cursor.fetchone()
        missing = []
        for table, column in REQUIRED_COLUMNS:
            cursor.execute(
                "SELECT 1 FROM information_schema.columns "
                "WHERE table_schema = DATABASE() AND table_name = %s "
                "AND column_name = %s",
                (table, column),
            )
            if cursor.fetchone() is None:
                missing.append(f"{table}.{column}")
        if missing:
            current_app.logger.error(
                "Database schema is missing required columns: %s. "
                "Run the database migrations before deploying the backend.",
                ", ".join(missing),
            )
            return jsonify({"status": "error", "db": "connected", "schema": "missing_required_columns"}), 503
        return jsonify({"status": "ok", "db": "connected"})
    except Error:
        current_app.logger.error("Database health check failed; connectivity or required schema could not be verified.")
        return jsonify({"status": "error", "db": "unavailable"}), 503
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None:
            conn.close()
