"""Filesystem containment policies for untrusted upload workflows."""

import os
from pathlib import Path


def ensure_within_root(root: str | Path, candidate: str | Path) -> Path:
    resolved_root = Path(root).resolve()
    resolved_candidate = Path(candidate).resolve()
    if os.path.commonpath((str(resolved_root), str(resolved_candidate))) != str(
        resolved_root
    ):
        raise RuntimeError("Path is outside the configured storage root")
    return resolved_candidate


def resolve_within_root(root: str | Path, *parts: str) -> Path:
    resolved_root = Path(root).resolve()
    return ensure_within_root(resolved_root, resolved_root.joinpath(*parts))
