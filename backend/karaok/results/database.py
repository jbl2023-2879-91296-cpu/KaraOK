"""Database implementation."""

from __future__ import annotations

from karaok.core.database import get_db


def _connection():

    return get_db()
