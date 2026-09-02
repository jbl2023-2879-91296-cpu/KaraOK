"""Owner-scoped amplifier profile and recommendation persistence services."""

from __future__ import annotations

import json
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Any, Mapping

from audio_thresholds import load_genre_profiles

from ...common.validation import bounded_number


PROFILE_FIELDS = {
    "name",
    "scale_min",
    "scale_max",
    "scale_step",
    "last_positions",
}
SCALE_FIELDS = ("scale_min", "scale_max", "scale_step")
KNOB_NAMES = ("volume", "bass", "treble", "sharpness", "flatness")


class ConflictError(RuntimeError):
    """Raised when valid input conflicts with the current resource state."""


def _connection():
    from ... import application

    return application.get_db()


def _finite_number(value: Any, field: str) -> float:
    return bounded_number(value, field, -9_999_999.999, 9_999_999.999)


def _name(value: Any) -> str:
    if not isinstance(value, str):
        raise ValueError("name must be text")
    cleaned = " ".join(value.strip().split())
    if not 1 <= len(cleaned) <= 80:
        raise ValueError("name must be 1-80 characters")
    return cleaned


def _scale(values: Mapping[str, Any]) -> tuple[float, float, float]:
    minimum = _finite_number(values["scale_min"], "scale_min")
    maximum = _finite_number(values["scale_max"], "scale_max")
    step = _finite_number(values["scale_step"], "scale_step")
    if minimum >= maximum:
        raise ValueError("scale_min must be less than scale_max")
    if step <= 0:
        raise ValueError("scale_step must be positive")
    if step > maximum - minimum:
        raise ValueError("scale_step must not exceed the scale range")
    return minimum, maximum, step


def _positions(
    value: Any,
    *,
    minimum: float,
    maximum: float,
) -> dict[str, float] | None:
    if value is None:
        return None
    if not isinstance(value, Mapping) or set(value) != set(KNOB_NAMES):
        raise ValueError("last_positions must contain exactly all five knob values")
    positions: dict[str, float] = {}
    for name in KNOB_NAMES:
        number = _finite_number(value[name], f"last_positions.{name}")
        if number < minimum or number > maximum:
            raise ValueError(
                f"last_positions.{name} must be between {minimum} and {maximum}"
            )
        positions[name] = number
    return positions


def _decoded_json(value: Any, field: str) -> Any:
    if value is None or isinstance(value, (dict, list)):
        return value
    if isinstance(value, bytes):
        value = value.decode("utf-8")
    if isinstance(value, str):
        try:
            return json.loads(value)
        except json.JSONDecodeError as error:
            raise ValueError(f"Stored {field} is not valid JSON") from error
    raise ValueError(f"Stored {field} has an unsupported value")


def _json_safe(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    return value


def _profile_response(row: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "id": int(row["amplifier_profile_id"]),
        "name": str(row["name"]),
        "scale_min": float(row["scale_min"]),
        "scale_max": float(row["scale_max"]),
        "scale_step": float(row["scale_step"]),
        "last_positions": _decoded_json(row.get("last_positions"), "last_positions"),
        "created_at": _json_safe(row.get("created_at")),
        "updated_at": _json_safe(row.get("updated_at")),
    }


def _recommendation_response(row: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "id": int(row["recommendation_id"]),
        "assessment_id": int(row["assessment_id"]),
        "amplifier_profile_id": int(row["amplifier_profile_id"]),
        "parent_recommendation_id": (
            int(row["parent_recommendation_id"])
            if row.get("parent_recommendation_id") is not None
            else None
        ),
        "genre": str(row["genre"]),
        "current": _decoded_json(row["current_positions"], "current_positions"),
        "recommended": _decoded_json(
            row["recommended_positions"], "recommended_positions"
        ),
        "adjustments": _decoded_json(row["adjustments"], "adjustments"),
        "original_score": float(row["original_score"]),
        "verification_score": (
            float(row["verification_score"])
            if row.get("verification_score") is not None
            else None
        ),
        "overall_confidence": str(row["overall_confidence"]),
        "algorithm_version": str(row["algorithm_version"]),
        "profile_version": str(row["genre_profile_version"]),
        "status": str(row["recommendation_status"]),
        "created_at": _json_safe(row.get("created_at")),
        "applied_at": _json_safe(row.get("applied_at")),
    }


def _select_profile(cursor, user_id: int, profile_id: int, *, lock: bool = False):
    cursor.execute(
        """SELECT amplifier_profile_id, user_id, name, scale_min, scale_max,
                  scale_step, last_positions, created_at, updated_at
           FROM amplifier_profile
           WHERE amplifier_profile_id = %s AND user_id = %s"""
        + (" FOR UPDATE" if lock else ""),
        (profile_id, user_id),
    )
    return cursor.fetchone()


def get_profile_metadata() -> dict[str, Any]:
    artifact = load_genre_profiles()
    return {
        "profile_version": artifact.profile_version,
        "enabled_genres": sorted(artifact.genres),
    }


def list_amplifier_profiles(user_id: int) -> list[dict[str, Any]]:
    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    try:
        cursor.execute(
            """SELECT amplifier_profile_id, user_id, name, scale_min, scale_max,
                      scale_step, last_positions, created_at, updated_at
               FROM amplifier_profile
               WHERE user_id = %s
               ORDER BY created_at, amplifier_profile_id""",
            (user_id,),
        )
        return [_profile_response(row) for row in cursor.fetchall()]
    finally:
        cursor.close()
        connection.close()


def get_amplifier_profile(user_id: int, profile_id: int) -> dict[str, Any]:
    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    try:
        row = _select_profile(cursor, user_id, profile_id)
        if row is None:
            raise LookupError("Amplifier profile was not found")
        return _profile_response(row)
    finally:
        cursor.close()
        connection.close()


def create_amplifier_profile(user_id: int, payload: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(payload, Mapping):
        raise ValueError("A JSON object is required")
    unexpected = set(payload).difference(PROFILE_FIELDS)
    if unexpected:
        raise ValueError(f"Profile contains unsupported fields: {sorted(unexpected)!r}")
    missing = {"name", *SCALE_FIELDS}.difference(payload)
    if missing:
        raise ValueError(f"Profile is missing required fields: {sorted(missing)!r}")

    name = _name(payload["name"])
    minimum, maximum, step = _scale(payload)
    positions = _positions(
        payload.get("last_positions"),
        minimum=minimum,
        maximum=maximum,
    )
    encoded_positions = (
        json.dumps(positions, sort_keys=True, separators=(",", ":"))
        if positions is not None
        else None
    )

    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    try:
        cursor.execute(
            """INSERT INTO amplifier_profile
               (user_id, name, scale_min, scale_max, scale_step, last_positions)
               VALUES (%s, %s, %s, %s, %s, %s)""",
            (user_id, name, minimum, maximum, step, encoded_positions),
        )
        profile_id = cursor.lastrowid
        row = _select_profile(cursor, user_id, profile_id)
        if row is None:
            raise RuntimeError("Created amplifier profile could not be loaded")
        connection.commit()
        return _profile_response(row)
    except Exception:
        connection.rollback()
        raise
    finally:
        cursor.close()
        connection.close()


def update_amplifier_profile(
    user_id: int,
    profile_id: int,
    payload: Mapping[str, Any],
) -> dict[str, Any]:
    if not isinstance(payload, Mapping) or not payload:
        raise ValueError("At least one profile field is required")
    unexpected = set(payload).difference(PROFILE_FIELDS)
    if unexpected:
        raise ValueError(f"Profile contains unsupported fields: {sorted(unexpected)!r}")

    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    rolled_back = False
    try:
        current = _select_profile(cursor, user_id, profile_id, lock=True)
        if current is None:
            connection.rollback()
            rolled_back = True
            raise LookupError("Amplifier profile was not found")

        effective = {
            "scale_min": payload.get("scale_min", current["scale_min"]),
            "scale_max": payload.get("scale_max", current["scale_max"]),
            "scale_step": payload.get("scale_step", current["scale_step"]),
        }
        minimum, maximum, step = _scale(effective)
        stored_positions = _decoded_json(current.get("last_positions"), "last_positions")
        positions = _positions(
            payload.get("last_positions", stored_positions),
            minimum=minimum,
            maximum=maximum,
        )

        updates: dict[str, Any] = {}
        if "name" in payload:
            updates["name"] = _name(payload["name"])
        for field, value in zip(SCALE_FIELDS, (minimum, maximum, step), strict=True):
            if field in payload:
                updates[field] = value
        if "last_positions" in payload:
            updates["last_positions"] = (
                json.dumps(positions, sort_keys=True, separators=(",", ":"))
                if positions is not None
                else None
            )

        cursor.execute(
            "UPDATE amplifier_profile SET "
            + ", ".join(f"{field} = %s" for field in updates)
            + ", updated_at = CURRENT_TIMESTAMP "
            + "WHERE amplifier_profile_id = %s AND user_id = %s",
            tuple(updates.values()) + (profile_id, user_id),
        )
        updated = _select_profile(cursor, user_id, profile_id)
        connection.commit()
        return _profile_response(updated)
    except Exception:
        if not rolled_back:
            connection.rollback()
        raise
    finally:
        cursor.close()
        connection.close()


def delete_amplifier_profile(user_id: int, profile_id: int) -> dict[str, Any]:
    connection = _connection()
    cursor = connection.cursor()
    rolled_back = False
    try:
        cursor.execute(
            """DELETE FROM amplifier_profile
               WHERE amplifier_profile_id = %s AND user_id = %s""",
            (profile_id, user_id),
        )
        if cursor.rowcount != 1:
            connection.rollback()
            rolled_back = True
            raise LookupError("Amplifier profile was not found")
        connection.commit()
        return {"id": profile_id, "message": "Amplifier profile deleted"}
    except Exception:
        if not rolled_back:
            connection.rollback()
        raise
    finally:
        cursor.close()
        connection.close()


def _recommendation_select(*, lock: bool) -> str:
    return (
        """SELECT sr.recommendation_id, sr.user_id, sr.assessment_id,
                  sr.amplifier_profile_id, sr.parent_recommendation_id,
                  sr.genre, sr.current_positions, sr.recommended_positions,
                  sr.adjustments, sr.original_score, sr.verification_score,
                  sr.overall_confidence, sr.algorithm_version,
                  sr.genre_profile_version, sr.recommendation_status,
                  sr.created_at, sr.applied_at,
                  ap.scale_min, ap.scale_max, ap.scale_step
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

        recommended = _decoded_json(
            row["recommended_positions"], "recommended_positions"
        )
        positions = _positions(
            recommended,
            minimum=float(row["scale_min"]),
            maximum=float(row["scale_max"]),
        )
        encoded_positions = json.dumps(
            positions,
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
