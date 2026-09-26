"""Artifacts implementation."""

from __future__ import annotations

from karaok.core.config import ANALYSIS_OUTPUT_DIR
from karaok.core.config import AUDIO_UPLOAD_DIR
from karaok.core.paths import ensure_within_root
from karaok.core.paths import resolve_within_root
from pathlib import Path
import shutil


def _analysis_directory(user_id: int, assessment_id: int) -> Path:
    destination = resolve_within_root(
        ANALYSIS_OUTPUT_DIR,
        str(user_id),
        str(assessment_id),
    )
    destination.mkdir(parents=True, exist_ok=True)
    return destination


def cleanup_audio_artifacts(
    user_id: int,
    assessment_id: int,
    temporary_audio_path: str | None = None,
) -> None:
    """Remove a temporary upload and an assessment's analyzer output safely."""
    upload_root = Path(AUDIO_UPLOAD_DIR).resolve()
    if temporary_audio_path:
        upload_path = ensure_within_root(upload_root, temporary_audio_path)
        upload_path.unlink(missing_ok=True)

    analysis_path = resolve_within_root(
        ANALYSIS_OUTPUT_DIR,
        str(user_id),
        str(assessment_id),
    )
    if analysis_path.is_dir():
        shutil.rmtree(analysis_path)


def _remove_temporary_audio(path: str) -> None:
    ensure_within_root(AUDIO_UPLOAD_DIR, path).unlink(missing_ok=True)


def _analysis_artifact_relative_path(path: Path) -> str:
    root = Path(ANALYSIS_OUTPUT_DIR).resolve()
    artifact = ensure_within_root(root, path)
    return artifact.relative_to(root).as_posix()
