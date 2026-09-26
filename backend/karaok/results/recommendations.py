"""Recommendations implementation."""

from __future__ import annotations

from datetime import datetime
from datetime import timezone
from karaok.core.recommendation_contracts import ConflictError
from karaok.core.recommendation_contracts import _decoded_json
from karaok.core.recommendation_contracts import _knob_settings
from karaok.core.recommendation_contracts import _recommendation_response
from karaok.core.recommendation_contracts import _same_scale
from karaok.core.recommendation_contracts import _stored_scale
from karaok.results.database import _connection
from typing import Any
import json


def _recommendation_select(*, lock: bool) -> str:
    return (
        """SELECT sr.recommendation_id, sr.user_id, sr.assessment_id,
                  sr.amplifier_profile_id, sr.parent_recommendation_id,
                  sr.genre, sr.current_positions, sr.recommended_positions,
                  sr.adjustments, sr.original_score, sr.verification_score,
                  sr.overall_confidence, sr.algorithm_version,
                  sr.genre_profile_version, sr.genre_profile_checksum,
                  sr.unavailable_message,
                  sr.recommendation_status,
                  sr.created_at, sr.applied_at,
                  sr.scale_min, sr.scale_max, sr.scale_step,
                  ap.scale_min AS profile_scale_min,
                  ap.scale_max AS profile_scale_max,
                  ap.scale_step AS profile_scale_step
           FROM settings_recommendation sr
           JOIN amplifier_profile ap
             ON ap.amplifier_profile_id = sr.amplifier_profile_id
            AND ap.user_id = sr.user_id
           WHERE sr.recommendation_id = %s
             AND sr.user_id = %s
             AND ap.user_id = %s"""
        + (" FOR UPDATE" if lock else "")
    )


def get_owned_recommendation(user_id: int, recommendation_id: int) -> dict[str, Any]:
    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    try:
        cursor.execute(
            _recommendation_select(lock=False),
            (recommendation_id, user_id, user_id),
        )
        row = cursor.fetchone()
        if row is None:
            raise LookupError("Settings recommendation was not found")
        return _recommendation_response(row)
    finally:
        cursor.close()
        connection.close()


def mark_recommendation_applied(
    user_id: int,
    recommendation_id: int,
) -> dict[str, Any]:
    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    rolled_back = False
    try:
        cursor.execute(
            _recommendation_select(lock=True),
            (recommendation_id, user_id, user_id),
        )
        row = cursor.fetchone()
        if row is None:
            connection.rollback()
            rolled_back = True
            raise LookupError("Settings recommendation was not found")
        if row["recommendation_status"] != "generated":
            connection.rollback()
            rolled_back = True
            raise ConflictError("Only a generated recommendation can be applied")

        snapshot_scale = _stored_scale(row)
        profile_scale = _stored_scale(row, prefix="profile_")
        if not _same_scale(snapshot_scale, profile_scale):
            connection.rollback()
            rolled_back = True
            raise ConflictError(
                "Amplifier profile scale changed after this recommendation was generated"
            )

        recommended = _decoded_json(
            row["recommended_positions"], "recommended_positions"
        )
        parsed_positions = _knob_settings(
            recommended,
            snapshot_scale,
            "recommended_positions",
        )
        encoded_positions = json.dumps(
            parsed_positions.to_dict(),
            sort_keys=True,
            separators=(",", ":"),
        )
        cursor.execute(
            """UPDATE amplifier_profile
               SET last_positions = %s, updated_at = CURRENT_TIMESTAMP
               WHERE amplifier_profile_id = %s AND user_id = %s""",
            (encoded_positions, row["amplifier_profile_id"], user_id),
        )
        cursor.execute(
            """UPDATE settings_recommendation
               SET recommendation_status = 'applied',
                   applied_at = UTC_TIMESTAMP()
               WHERE recommendation_id = %s AND user_id = %s
                 AND recommendation_status = 'generated'""",
            (recommendation_id, user_id),
        )
        if cursor.rowcount != 1:
            raise ConflictError("Recommendation state changed before it was applied")
        connection.commit()

        applied = dict(row)
        applied["recommendation_status"] = "applied"
        applied["applied_at"] = datetime.now(timezone.utc)
        return _recommendation_response(applied)
    except Exception:
        if not rolled_back:
            connection.rollback()
        raise
    finally:
        cursor.close()
        connection.close()
