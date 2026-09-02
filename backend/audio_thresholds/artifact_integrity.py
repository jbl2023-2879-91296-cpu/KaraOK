"""Canonical integrity helpers for generated quality artifacts."""

from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping
from typing import Any


def canonical_artifact_checksum(data: Mapping[str, Any]) -> str:
    """Return the SHA-256 checksum of canonical artifact content."""

    unsigned = dict(data)
    unsigned.pop("artifact_checksum", None)
    canonical = json.dumps(
        unsigned, sort_keys=True, separators=(",", ":"), allow_nan=False
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()
