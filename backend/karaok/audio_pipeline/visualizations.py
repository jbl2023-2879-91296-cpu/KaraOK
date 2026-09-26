"""Visualizations implementation."""

from __future__ import annotations

from karaok.core.config import ANALYSIS_OUTPUT_DIR
from karaok.core.artifacts import _analysis_artifact_relative_path
from karaok.core.paths import ensure_within_root
from pathlib import Path
from typing import Any
import base64


def _visualization_paths(destination: Path) -> dict[str, str]:
    paths: dict[str, str] = {}
    for kind in ("waveform", "spectrogram"):
        matches = sorted(
            destination.glob(f"*_{kind}.png"),
            key=lambda path: path.stat().st_mtime,
            reverse=True,
        )
        if not matches:
            raise RuntimeError(f"Analyzer did not produce the {kind} visualization")
        paths[kind] = _analysis_artifact_relative_path(matches[0])
    return paths


def _guest_visualization_images(dump: dict[str, Any]) -> dict[str, str]:
    images: dict[str, str] = {}
    visualizations = dump.get("visualizations")
    if not isinstance(visualizations, dict):
        return images
    for kind in ("waveform", "spectrogram"):
        relative_path = visualizations.get(kind)
        if not isinstance(relative_path, str):
            continue
        artifact = ensure_within_root(
            ANALYSIS_OUTPUT_DIR,
            Path(ANALYSIS_OUTPUT_DIR).resolve() / relative_path,
        )
        images[kind] = base64.b64encode(artifact.read_bytes()).decode("ascii")
    return images
