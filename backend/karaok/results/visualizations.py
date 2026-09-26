"""Visualizations implementation."""

from __future__ import annotations

from flask import g
from flask import jsonify
from flask import send_file
from karaok.auth.access import require_auth
from karaok.core.config import ANALYSIS_OUTPUT_DIR
from karaok.core.database import get_db
from karaok.core.paths import ensure_within_root
from karaok.core.runtime import app
from pathlib import Path


@require_auth("user")
def get_audio_visualization(test_id: int, kind: str):
    if kind not in {"waveform", "spectrogram"}:
        return jsonify({"error": "Visualization not found"}), 404
    column = f"{kind}_path"
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        f"""SELECT r.{column} AS artifact_path
            FROM assessment a
            JOIN audio_analysis_result r
              ON r.assessment_id = a.assessment_id
            WHERE a.assessment_id = %s AND a.user_id = %s""",
        (test_id, g.user_id),
    )
    record = cursor.fetchone()
    cursor.close()
    conn.close()
    relative_path = record.get("artifact_path") if record else None
    if not isinstance(relative_path, str):
        return jsonify({"error": "Visualization not found"}), 404
    try:
        artifact = ensure_within_root(
            ANALYSIS_OUTPUT_DIR,
            Path(ANALYSIS_OUTPUT_DIR).resolve() / relative_path,
        )
    except RuntimeError:
        app.logger.error("Refused to serve an invalid visualization path")
        return jsonify({"error": "Visualization not found"}), 404
    if not artifact.is_file():
        return jsonify({"error": "Visualization not found"}), 404
    return send_file(
        artifact,
        mimetype="image/png",
        conditional=True,
        max_age=3600,
    )
