"""Email identity and domain policy for public registration."""

import karaok.core.config as config
from karaok.core.passwords import clean_email


def canonical_email(email: str) -> str:
    local, domain = email.strip().lower().rsplit("@", 1)
    local = local.split("+", 1)[0]
    if domain in ("gmail.com", "googlemail.com"):
        local, domain = local.replace(".", ""), "gmail.com"
    return f"{local}@{domain}"


def is_allowed_domain(email: str) -> bool:
    return email.lower().rpartition("@")[2] in config.ALLOWED_EMAIL_DOMAINS


def clean_registration_email(value) -> str:
    email = clean_email(value)
    if not is_allowed_domain(email):
        raise ValueError("email domain is not supported")
    return email
