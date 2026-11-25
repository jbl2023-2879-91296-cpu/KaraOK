from io import BytesIO
import json
import os
from pathlib import Path
import subprocess
import sys
from unittest.mock import MagicMock, patch
import wave

import numpy as np
import pytest
import soundfile as sf

os.environ.setdefault("JWT_SECRET", "test-only-secret-that-is-at-least-32-characters")

import app as api
from audio_engine.analyzer import AudioAnalysisError, analyze_audio
from audio_engine.mic_calibration import (
    compute_offsets,
    measure_calibration_recording,
    validate_correction,
)
from karaok.audio_pipeline import calibration, pipeline
from karaok.audio_pipeline.summary import _score_analyzer_output
from karaok.results import records
from noise_fixtures import music_like
from test_audio_pipeline import _analyzer_result

SR = 44100
ROOT = Path(__file__).resolve().parents[2]
REFERENCE_WAV = ROOT / "docs/calibration/karaok_pink_noise_30s.wav"
MIC_WARNING = (
    "The song was quiet compared with this phone's own microphone hiss. "
    "Move the phone closer to the speaker or raise the volume."
)
ROOM_WARNING = "Background noise is loud compared with the song. Move the phone closer to the speaker."


def phone_response(samples):
    frequency = np.fft.rfftfreq(samples.size, 1 / SR)
    shelf_db = np.where(frequency < 200, -6, np.where(frequency > 6000, 3, 0))
    return np.fft.irfft(np.fft.rfft(samples) * 10 ** ((shelf_db - 8) / 20), n=samples.size)


@pytest.fixture(scope="module")
def phone_samples():
    pink, _ = sf.read(REFERENCE_WAV, frames=15 * SR)
    floor = np.random.default_rng(8).normal(0, 10 ** (-70 / 20), 5 * SR)
    return pink, floor


@pytest.fixture(scope="module")
def correction(phone_samples):
    pink, floor = phone_samples
    reference = dict(measure_calibration_recording(np.r_[floor, pink], SR), reference_id="ref")
    measured = measure_calibration_recording(np.r_[floor, phone_response(pink)], SR)
    return compute_offsets(measured, reference)


def analyze_pair(tmp_path, source, correction):
    reference = tmp_path / "reference.wav"
    phone = tmp_path / "phone.wav"
    sf.write(reference, source, SR, subtype="FLOAT")
    sf.write(phone, phone_response(source), SR, subtype="FLOAT")
    return analyze_audio(reference), analyze_audio(phone), analyze_audio(phone, mic_calibration=correction)


def test_corrected_loudness_and_band_energy_match_reference(tmp_path, phone_samples, correction):
    pink, _ = phone_samples
    reference, raw, corrected = analyze_pair(tmp_path, pink, correction)
    for group, field, tolerance in (
        ("loudness", "integrated_lufs", 0.5),
        ("bass", "energy_percentage", 1),
        ("treble", "energy_percentage", 1),
    ):
        assert corrected[group][field] == pytest.approx(reference[group][field], abs=tolerance)
    assert corrected["distortion"] == raw["distortion"]
    assert corrected["noise"] == raw["noise"]


def test_correction_reduces_song_score_difference(tmp_path, correction):
    analyses = analyze_pair(tmp_path, music_like(SR, 15, 7), correction)
    reference, raw, corrected = [_score_analyzer_output(result)["overall_score"] for result in analyses]
    assert abs(reference - raw) > 2
    assert abs(reference - corrected) <= 2


@pytest.mark.parametrize(("case", "message"), [
    ("short", "Record at least 12 seconds of the reference sound after the silent part."),
    ("clip", "The reference sound was too loud for this phone. Lower the machine volume one step or move back, then try again."),
    ("quiet", "The reference sound was too quiet compared with the silence. Raise the machine volume or move closer, then try again."),
    ("noisy", "The room was not quiet during the first 5 seconds. Stay silent until the app says to start the sound."),
])
def test_recording_validation(case, message, phone_samples):
    pink, floor = phone_samples
    if case == "short":
        pink = pink[:6 * SR]
    elif case == "clip":
        pink = np.clip(pink * 12, -1, 1)
    elif case == "quiet":
        pink = pink * 0.001
    elif case == "noisy":
        time = np.arange(floor.size) / SR
        floor = 0.06 * np.sin(2 * np.pi * 125 * time)
    with pytest.raises(AudioAnalysisError) as error:
        measure_calibration_recording(np.r_[floor, pink], SR)
    assert str(error.value) == message


@pytest.mark.parametrize("fields", [
    {"band_offsets_db": [2] * 8},
    {"band_offsets_db": [float("nan")] * 9},
    {"band_offsets_db": [13] * 9},
    {"level_offset_db": 21},
    {"version": True},
])
def test_correction_schema(fields, correction):
    assert validate_correction(correction) == correction
    with pytest.raises(ValueError):
        validate_correction({**correction, **fields})


def wav_upload(samples):
    data = BytesIO()
    with wave.open(data, "wb") as wav:
        wav.setparams((1, 2, SR, 0, "NONE", "not compressed"))
        wav.writeframes(np.rint(samples * 32767).astype("<i2").tobytes())
    data.seek(0)
    return data, "phone.wav"


def test_calibration_endpoint_reference_log_and_cleanup(tmp_path, monkeypatch, phone_samples):
    pink, floor = phone_samples
    reference_path = tmp_path / "reference.json"
    monkeypatch.setattr(calibration, "AUDIO_UPLOAD_DIR", str(tmp_path))
    monkeypatch.setattr(calibration, "REFERENCE_PATH", reference_path)
    client = api.app.test_client()
    endpoint = "/api/guest/mic-calibration"
    first = client.post(endpoint, data={"audio": wav_upload(np.r_[floor, pink]), "device_label": " device "})
    assert first.status_code == 200
    assert first.json["correction"] is None
    assert first.json["reference_available"] is False
    directory = tmp_path / "calibration"
    log = directory / "measurements.jsonl"
    entry = json.loads(log.read_text(encoding="utf-8"))
    assert entry["measurement_id"] == first.json["measurement_id"]
    assert entry["device_label"] == "device"
    assert entry["user_id"] == "guest"
    assert list(directory.iterdir()) == [log]

    script = ROOT / "backend/scripts/set_mic_calibration_reference.py"
    command = [sys.executable, str(script), "--log", str(log), "--out", str(reference_path), "--measurement-id"]
    missing = subprocess.run([*command, "missing"], capture_output=True, text=True)
    assert missing.returncode == 1
    assert "was not found" in missing.stdout
    found = subprocess.run([*command, entry["measurement_id"]], capture_output=True, text=True)
    assert found.returncode == 0
    assert json.loads(found.stdout)["reference_id"] == entry["measurement_id"]

    second = client.post(endpoint, data={"audio": wav_upload(np.r_[floor, phone_response(pink)])})
    assert second.status_code == 200
    assert second.json["reference_available"] is True
    assert validate_correction(second.json["correction"])["reference_id"] == entry["measurement_id"]
    bad = client.post(endpoint, data={"audio": wav_upload(np.r_[floor, pink[:5 * SR]])})
    assert bad.status_code == 422
    assert bad.json["error"].startswith("Record at least 12 seconds")
    assert len(log.read_text(encoding="utf-8").splitlines()) == 2
    assert list(directory.iterdir()) == [log]
    assert client.post("/api/mic-calibration", data={}).status_code == 401


def test_analysis_upload_rejects_invalid_correction():
    response = api.app.test_client().post("/api/guest/audio-analysis", data={
        "audio": (BytesIO(b"RIFF-test"), "recording.wav"),
        "duration_seconds": "20",
        "mic_calibration": "{bad json}",
    })
    assert response.status_code == 400
    assert response.json["field"] == "mic_calibration"


def test_authenticated_upload_persists_calibration(tmp_path, correction):
    analysis = _analyzer_result()
    analysis["mic_calibration"] = {**correction, "applied": True}
    analysis["noise_guard"] = {"noise_source": "phone_microphone"}
    dump = {
        "analysis": analysis,
        "analyzer_process": {"duration_seconds": 1},
        "visualizations": {"waveform": "w.png", "spectrogram": "s.png"},
    }
    database = MagicMock()
    cursor = database.cursor.return_value
    with api.app.test_request_context("/api/audio-uploads", method="POST", data={
        "audio": (BytesIO(b"RIFF-test"), "recording.wav"),
        "duration_seconds": "20",
        "mic_calibration": json.dumps(correction),
        "mic_noise_floor_dbfs": "-55",
    }), patch.object(pipeline, "AUDIO_UPLOAD_DIR", str(tmp_path)), patch.object(
        pipeline, "audio_duration_seconds", return_value=20,
    ), patch.object(
        pipeline, "run_audio_analyzer", return_value=dump,
    ) as analyzer, patch.object(
        pipeline, "create_audio_upload_records", return_value=(11, 13),
    ), patch.object(records, "get_db", return_value=database), patch.object(pipeline, "audit"):
        api.g.user_id = 7
        response, status = pipeline.create_audio_upload.__wrapped__()
    assert status == 201
    assert analyzer.call_args.kwargs["mic_calibration"] == correction
    assert analyzer.call_args.kwargs["mic_noise_floor_dbfs"] == -55
    assert response.json["mic_calibration"]["applied"] is True
    insert = next(call.args[1] for call in cursor.execute.call_args_list if "INSERT INTO" in call.args[0] and "empirical_details" in call.args[0])
    detail = next(json.loads(value) for value in insert if isinstance(value, str) and '"mic_calibration"' in value)
    assert detail["mic_calibration"]["applied"] is True
    assert detail["noise_source"] == "phone_microphone"


@pytest.mark.parametrize(("above_floor", "source", "warning"), [
    (0, "phone_microphone", MIC_WARNING),
    (10, "room", ROOM_WARNING),
])
def test_noise_source(above_floor, source, warning, tmp_path):
    rng = np.random.default_rng(21)
    level = 10 ** ((-55 + above_floor) / 20)
    noise = rng.normal(0, level, SR * 15)
    song = noise[3 * SR:] + music_like(SR, 12, 21) * level * 20
    path = tmp_path / "room.wav"
    sf.write(path, np.r_[noise[:3 * SR], song], SR, subtype="FLOAT")
    result = analyze_audio(path, noise_preroll_seconds=3, mic_noise_floor_dbfs=-55)
    assert result["noise_guard"]["noise_source"] == source
    assert warning in result["noise_guard"]["warnings"]
