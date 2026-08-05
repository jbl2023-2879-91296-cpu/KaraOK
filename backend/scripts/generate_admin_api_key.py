"""Generate a Data Administration API key and its server-side SHA-256 hash."""

from __future__ import annotations

import hashlib
import secrets


raw_key = secrets.token_urlsafe(48)
key_hash = hashlib.sha256(raw_key.encode("utf-8")).hexdigest()

print("Store this raw value only in admin/.env as ADMIN_API_KEY:")
print(raw_key)
print()
print("Store this hash only in backend/.env as ADMIN_DATA_API_KEY_HASH:")
print(key_hash)
