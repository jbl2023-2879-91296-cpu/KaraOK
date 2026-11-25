"""Relative microphone response measurement and correction."""

import math

import librosa
import numpy as np
from scipy.signal import welch

OCTAVE_CENTERS_HZ = (63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000)
MID_BANDS = slice(2, 7)
SHORT_RECORDING = "Record at least 12 seconds of the reference sound after the silent part."
QUIET_REFERENCE = (
    "The reference sound was too quiet compared with the silence. "
    "Raise the machine volume or move closer, then try again."
)


class CalibrationMeasurement(dict):
    """JSON-compatible measurements with the pink segment kept in memory."""

    def __init__(self, values, pink_audio, sample_rate):
        super().__init__(values)
        self.pink_audio = pink_audio
        self.sample_rate = sample_rate


def _loudness(audio, sample_rate):
    from .analyzer import AudioAnalysisError, _bs1770_filtered_mono, _integrated_lufs

    result = _integrated_lufs(_bs1770_filtered_mono(audio, sample_rate))
    if result is None:
        raise AudioAnalysisError(QUIET_REFERENCE)
    return result


def _band_levels(audio, sample_rate):
    frequencies, density = welch(audio, fs=sample_rate, nperseg=min(8192, audio.size))
    levels = []
    for center in OCTAVE_CENTERS_HZ:
        band = (frequencies >= center / math.sqrt(2)) & (frequencies < center * math.sqrt(2))
        power = np.sum(density[band]) * (frequencies[1] - frequencies[0])
        levels.append(float(10 * np.log10(max(power, 1e-12))))
    return levels


def measure_calibration_recording(audio, sample_rate, silence_seconds=5.0, settle_seconds=2.0):
    from .analyzer import AudioAnalysisError

    half_second = round(0.5 * sample_rate)
    floor = audio[half_second:round(silence_seconds * sample_rate)]
    pink = audio[round((silence_seconds + settle_seconds) * sample_rate): audio.size - half_second]
    if pink.size < 10 * sample_rate or floor.size < 2:
        raise AudioAnalysisError(SHORT_RECORDING)
    clipped = 100 * float(np.mean(np.abs(audio) >= 0.999))
    if clipped > 0.1:
        raise AudioAnalysisError(
            "The reference sound was too loud for this phone. Lower the machine volume one step or move back, then try again."
        )
    floor_dbfs = float(10 * np.log10(max(np.mean(np.square(floor)), 1e-12)))
    band_levels = _band_levels(pink, sample_rate)
    band_floor = _band_levels(floor, sample_rate)
    if floor_dbfs > -30:
        raise AudioAnalysisError(
            "The room was not quiet during the first 5 seconds. Stay silent until the app says to start the sound."
        )
    if np.median((np.array(band_levels) - band_floor)[MID_BANDS]) < 20:
        raise AudioAnalysisError(QUIET_REFERENCE)
    return CalibrationMeasurement({
        "noise_floor_dbfs": floor_dbfs,
        "pink_lufs": _loudness(pink, sample_rate),
        "band_levels_db": band_levels,
        "band_floor_db": band_floor,
        "clipped_percentage": clipped,
        "pink_seconds": pink.size / sample_rate,
    }, pink, sample_rate)


def compute_offsets(measurement: CalibrationMeasurement, reference: dict) -> dict:
    phone = np.asarray(measurement["band_levels_db"])
    target = np.asarray(reference["band_levels_db"])
    offsets = (target - np.mean(target[MID_BANDS])) - (phone - np.mean(phone[MID_BANDS]))
    reliable = ((phone - measurement["band_floor_db"] >= 10)
                & (target - reference["band_floor_db"] >= 10))
    offsets = np.where(reliable, offsets, 0.0)
    eq = np.clip(offsets, -12, 12)
    correction = {
        "version": 1,
        "level_offset_db": 0.0,
        "band_centers_hz": list(OCTAVE_CENTERS_HZ),
        "band_offsets_db": eq.tolist(),
        "reference_id": reference["reference_id"],
    }
    sample_rate = measurement.sample_rate
    equalized = apply_correction(measurement.pink_audio, sample_rate, correction)
    gain = reference["pink_lufs"] - _loudness(equalized, sample_rate)
    correction["level_offset_db"] = float(np.clip(gain, -20, 20))
    correction["clamped"] = bool(np.any(offsets != eq) or abs(gain) > 20)
    return correction


def validate_correction(obj):
    def valid_number(value, limit):
        return type(value) in (int, float) and -limit <= value <= limit

    if not isinstance(obj, dict) or type(obj.get("version")) is not int or obj["version"] != 1:
        raise ValueError("mic_calibration must have version 1")
    centers = obj.get("band_centers_hz")
    offsets = obj.get("band_offsets_db")
    level = obj.get("level_offset_db")
    if not isinstance(centers, (tuple, list)) or tuple(centers) != OCTAVE_CENTERS_HZ:
        raise ValueError("mic_calibration has invalid octave band centers")
    if not isinstance(offsets, list) or len(offsets) != 9 or not all(valid_number(value, 12) for value in offsets):
        raise ValueError("mic_calibration requires nine band offsets between -12 and 12 dB")
    if not valid_number(level, 20):
        raise ValueError("mic_calibration level offset must be between -20 and 20 dB")
    reference_id = obj.get("reference_id")
    if reference_id is not None and (not isinstance(reference_id, str) or len(reference_id) > 80):
        raise ValueError("mic_calibration has an invalid reference ID")
    clamped = obj.get("clamped", False)
    if type(clamped) is not bool:
        raise ValueError("mic_calibration clamped must be a boolean")
    return {
        "version": 1, "band_centers_hz": list(OCTAVE_CENTERS_HZ),
        "band_offsets_db": offsets, "level_offset_db": level,
        "reference_id": reference_id, "clamped": clamped,
    }


def apply_correction(audio, sample_rate, correction, frame_length=4096, hop_length=1024):
    audio = np.asarray(audio, dtype=np.float64)
    spectrum = librosa.stft(audio, n_fft=frame_length, hop_length=hop_length, window="hann")
    frequencies = librosa.fft_frequencies(sr=sample_rate, n_fft=frame_length)
    band_db = np.interp(
        np.log2(np.maximum(frequencies, OCTAVE_CENTERS_HZ[0])),
        np.log2(OCTAVE_CENTERS_HZ),
        correction["band_offsets_db"],
    )
    gain = 10 ** ((correction["level_offset_db"] + band_db) / 20)
    return librosa.istft(
        spectrum * gain[:, None], n_fft=frame_length, hop_length=hop_length,
        window="hann", length=audio.size,
    )
