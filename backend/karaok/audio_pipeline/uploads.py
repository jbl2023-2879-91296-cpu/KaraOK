"""Uploads implementation."""

from __future__ import annotations

from karaok.core.config import MAX_AUDIO_SECONDS
from mutagen import File as MutagenFile
import math


MIDI_RENDERED_AUDIO_MESSAGE = (
    "MIDI event files are not rendered audio. Record the karaoke machine playback "
    "or select WAV, MP3, M4A, AAC, OGG, or FLAC."
)


class AudioDurationError(ValueError):
    """Readable audio that falls outside the supported upload duration."""


def audio_duration_seconds(path: str) -> int:
    """Return a validated whole-second duration for a readable audio stream."""
    try:
        audio_info = MutagenFile(path)
    except Exception as error:
        raise ValueError("No readable audio stream found") from error
    if audio_info is None or audio_info.info is None:
        raise ValueError("No readable audio stream found")
    duration = float(audio_info.info.length)
    if not math.isfinite(duration) or duration < 10 or duration > MAX_AUDIO_SECONDS:
        raise AudioDurationError("Audio duration must be between 10 and 300 seconds")
    return int(round(duration))
