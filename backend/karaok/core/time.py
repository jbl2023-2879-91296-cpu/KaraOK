"""Time implementation."""

from __future__ import annotations

from datetime import datetime
from datetime import timezone


def utcnow() -> datetime:
    return datetime.now(timezone.utc)
