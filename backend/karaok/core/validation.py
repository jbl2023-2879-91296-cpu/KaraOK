"""Reusable request and primitive validation helpers."""

from typing import Any

from flask import request


def json_body() -> dict[str, Any]:
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        raise ValueError("A JSON object is required")
    return data


def clean_text(value: Any, field: str, minimum: int, maximum: int) -> str:
    if not isinstance(value, str):
        raise ValueError(f"{field} must be text")
    cleaned = " ".join(value.strip().split())
    if not minimum <= len(cleaned) <= maximum:
        raise ValueError(f"{field} must be {minimum}-{maximum} characters")
    return cleaned


def bounded_number(
    value: Any,
    field: str,
    minimum: float,
    maximum: float,
) -> float:
    if isinstance(value, bool):
        raise ValueError(f"{field} must be numeric")
    try:
        number = float(value)
    except (TypeError, ValueError) as error:
        raise ValueError(f"{field} must be numeric") from error
    if not minimum <= number <= maximum:
        raise ValueError(f"{field} must be between {minimum} and {maximum}")
    return number
