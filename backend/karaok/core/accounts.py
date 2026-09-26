"""Accounts implementation."""

from __future__ import annotations

from datetime import datetime
from karaok.core.config import MAX_PROFILE_IMAGE_BYTES
from karaok.core.time import utcnow
from karaok.core.validation import clean_text
from typing import Any
import base64
import binascii
import re


def _clean_profile_image(data: dict[str, Any]) -> tuple[bytes | None, str | None]:
    encoded = data.get("profile_image_base64")
    mime_type = data.get("profile_image_mime")
    if encoded in (None, ""):
        return None, None
    if not isinstance(encoded, str) or not isinstance(mime_type, str):
        raise ValueError("profile image is invalid")
    supported_mime_types = {
        "image/jpeg",
        "image/png",
        "image/webp",
        "image/gif",
        "image/heic",
        "image/heif",
        "image/avif",
        "image/bmp",
    }
    if mime_type not in supported_mime_types:
        raise ValueError("profile image uses an unsupported image format")
    size_limit = f"{MAX_PROFILE_IMAGE_BYTES / (1024 * 1024):g} MB"
    if len(encoded) > ((MAX_PROFILE_IMAGE_BYTES * 4 // 3) + 16):
        raise ValueError(f"profile image must not exceed {size_limit}")
    try:
        image = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError) as error:
        raise ValueError("profile image is invalid") from error
    if not image or len(image) > MAX_PROFILE_IMAGE_BYTES:
        raise ValueError(f"profile image must not exceed {size_limit}")
    iso_brand = image[8:12] if len(image) >= 12 and image[4:8] == b"ftyp" else b""
    signatures = {
        "image/jpeg": image.startswith(b"\xff\xd8\xff"),
        "image/png": image.startswith(b"\x89PNG\r\n\x1a\n"),
        "image/webp": image.startswith(b"RIFF") and image[8:12] == b"WEBP",
        "image/gif": image.startswith((b"GIF87a", b"GIF89a")),
        "image/heic": iso_brand
        in {b"heic", b"heix", b"hevc", b"hevx", b"heim", b"heis", b"mif1", b"msf1"},
        "image/heif": iso_brand in {b"mif1", b"msf1"},
        "image/avif": iso_brand in {b"avif", b"avis"},
        "image/bmp": image.startswith(b"BM"),
    }
    if not signatures[mime_type]:
        raise ValueError("profile image content does not match its file type")
    return image, mime_type


def _clean_birthday(value: Any) -> str:
    if not isinstance(value, str):
        raise ValueError("birthday is required")
    try:
        birthday = datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError as error:
        raise ValueError("birthday must use YYYY-MM-DD") from error
    if birthday >= utcnow().date():
        raise ValueError("birthday must be in the past")
    return birthday.isoformat()


def _clean_phone(value: Any) -> str:
    phone = clean_text(value, "phone_number", 7, 24)
    if not re.fullmatch(r"\+?[0-9 ()-]{7,24}", phone):
        raise ValueError("phone_number is invalid")
    prefix = "+" if phone.startswith("+") else ""
    digits = re.sub(r"\D", "", phone)
    if len(digits) < 7 or len(digits) > 15:
        raise ValueError("phone_number must contain 7-15 digits")
    return f"{prefix}{digits}"


def _profile_response(user: dict[str, Any]) -> dict[str, Any]:
    first_name = user.get("first_name", "")
    last_name = user.get("last_name", "")
    image = user.get("profile_image")
    return {
        "id": user["user_id"],
        "username": user["username"],
        "name": " ".join(part for part in (first_name, last_name) if part),
        "first_name": first_name,
        "last_name": last_name,
        "email": user["email"],
        "address": user.get("address", ""),
        "city": user.get("city", ""),
        "state_province": user.get("state_province", ""),
        "area_code": user.get("area_code", ""),
        "country": user.get("country", ""),
        "country_code": user.get("country_code", ""),
        "phone_number": user.get("phone_number", ""),
        "birthday": str(user.get("birthday") or ""),
        "profile_image_base64": base64.b64encode(bytes(image)).decode("ascii")
        if image
        else None,
        "profile_image_mime": user.get("profile_image_mime"),
        "user_type": user["user_type"],
        "requires_password_change": bool(
            user.get("requires_password_change", False)
        ),
    }
