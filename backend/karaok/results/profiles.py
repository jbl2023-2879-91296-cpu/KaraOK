"""Profiles implementation."""

from __future__ import annotations

from karaok.core.recommendation_contracts import KNOB_NAMES
from karaok.core.recommendation_contracts import _decoded_json
from karaok.core.recommendation_contracts import _json_safe
from karaok.core.validation import bounded_number
from karaok.results.database import _connection
from typing import Any
from typing import Mapping
import json


PROFILE_FIELDS = {
    "name",
    "scale_min",
    "scale_max",
    "scale_step",
    "last_positions",
}


SCALE_FIELDS = ("scale_min", "scale_max", "scale_step")


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
