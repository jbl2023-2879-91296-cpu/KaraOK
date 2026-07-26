"""Password policy, hashing, email normalization, and secret hashing."""

import hashlib
import re
import secrets
from typing import Any

from argon2 import PasswordHasher

from ..common.validation import clean_text


EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
password_hasher = PasswordHasher(time_cost=2, memory_cost=19456, parallelism=1)


def clean_email(value: Any) -> str:
    email = clean_text(value, "email", 5, 254).lower()
    if not EMAIL_RE.fullmatch(email):
        raise ValueError("email is invalid")
    return email


def validate_password(password: Any) -> str:
    if not isinstance(password, str) or not 12 <= len(password) <= 128:
        raise ValueError("password must be 12-128 characters")
    if not (re.search(r"[A-Z]", password) and re.search(r"[a-z]", password)):
        raise ValueError("password must include uppercase and lowercase letters")
    if not re.search(r"\d", password) or not re.search(r"[^A-Za-z0-9]", password):
        raise ValueError("password must include a number and symbol")
    return password


def generate_temporary_password(length: int = 20) -> str:
    """Generate a policy-compliant password intended for one-time login."""
    uppercase = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    lowercase = "abcdefghijkmnopqrstuvwxyz"
    digits = "23456789"
    symbols = "!@#$%&*-_"
    characters = uppercase + lowercase + digits + symbols
    password = [
        secrets.choice(uppercase),
        secrets.choice(lowercase),
        secrets.choice(digits),
        secrets.choice(symbols),
    ]
    password.extend(secrets.choice(characters) for _ in range(length - len(password)))
    secrets.SystemRandom().shuffle(password)
    return "".join(password)


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()
