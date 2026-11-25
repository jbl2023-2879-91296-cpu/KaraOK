"""Microphone calibration upload and measurement storage."""

from datetime import datetime, timezone
import json
from pathlib import Path
import secrets
from tempfile import TemporaryDirectory

from flask import g, jsonify, request
import soundfile as sf
from werkzeug.utils import secure_filename

from audio_engine.analyzer import AnalyzerConfig, AudioAnalysisError, load_audio, validate_audio
from audio_engine.mic_calibration import compute_offsets, measure_calibration_recording
from karaok.auth.access import require_auth
from karaok.core.config import AUDIO_UPLOAD_DIR, BACKEND_DIR, MAX_AUDIO_BYTES
from karaok.core.runtime import limiter

REFERENCE_PATH = BACKEND_DIR / "audio_thresholds" / "mic_calibration_reference.json"
NO_REFERENCE = (
    "Measured. No reference phone is set on the server yet, so no correction was saved. "
    "Set the reference, then calibrate again."
)


@require_auth("user")
def calibrate_user():
    return _calibrate(g.user_id)


@limiter.limit("10 per hour")
def calibrate_guest():
    return _calibrate("guest")


def _calibrate(user_id):
    upload = request.files.get("audio")
    if upload is None or not upload.filename:
        return jsonify(error="A multipart audio file is required in the 'audio' field"), 400
    if Path(secure_filename(upload.filename)).suffix.lower() != ".wav":
        return jsonify(error="Unsupported audio format"), 415

    directory = Path(AUDIO_UPLOAD_DIR) / "calibration"
    directory.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(dir=directory) as temporary:
        path = Path(temporary) / "recording.wav"
        upload.save(path)
        if not 0 < path.stat().st_size <= MAX_AUDIO_BYTES:
            return jsonify(error=f"Audio file is empty or exceeds the {MAX_AUDIO_BYTES / (1024 * 1024):g} MiB limit"), 413
        try:
            with sf.SoundFile(path) as container:
                if container.format not in {"WAV", "WAVEX", "RF64"}:
                    return jsonify(error="Unsupported audio format"), 415
            audio, sample_rate, _ = load_audio(path)
            audio = validate_audio(audio, sample_rate, AnalyzerConfig())
            measurement = measure_calibration_recording(audio, sample_rate)
        except AudioAnalysisError as error:
            return jsonify(error=str(error).replace(str(path), "recording")), 422
        except (OSError, sf.LibsndfileError):
            return jsonify(error="Audio file is corrupted or unreadable"), 422

    measurement_id = secrets.token_hex(4)
    entry = {
        "measurement_id": measurement_id,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "user_id": user_id,
        "device_label": request.form.get("device_label", "").strip()[:80],
        **measurement,
    }
    with (directory / "measurements.jsonl").open("a", encoding="utf-8", newline="\n") as log:
        log.write(json.dumps(entry, allow_nan=False) + "\n")
    try:
        reference = json.loads(REFERENCE_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError:
        reference = None
    try:
        correction = None if reference is None else compute_offsets(measurement, reference)
    except AudioAnalysisError as error:
        return jsonify(error=str(error)), 422
    return jsonify(
        measurement_id=measurement_id,
        noise_floor_dbfs=measurement["noise_floor_dbfs"],
        pink_lufs=measurement["pink_lufs"],
        reference_available=reference is not None,
        correction=correction,
        message=NO_REFERENCE if correction is None else "Calibrated",
    )
