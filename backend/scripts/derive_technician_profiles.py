"""Rebuild genre targets from the project's 45 technician speaker recordings.

Run from the repository root: python backend/scripts/derive_technician_profiles.py
Raw recordings remain local; only measurements, provenance and targets are shipped.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))
from audio_engine import analyze_audio, load_audio
from audio_thresholds.derive_genre_profiles import FEATURE_PATHS, METRIC_UNITS
from audio_thresholds.artifact_integrity import canonical_artifact_checksum
from audio_thresholds.genre_profiles import parse_genre_profile_artifact


def target(values, unit, *, strict=True):
    low, median, high = map(float, np.quantile(values, [0.25, 0.5, 0.75]))
    spread = max(high - low, abs(median) * .05, 1e-9)
    if strict and not low < median < high:
        raise ValueError(f"Insufficient variation for {unit}; inspect reference recordings")
    return dict(lower=low, preferred=median, upper=high, robust_scale=spread, unit=unit)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--songs', type=Path, default=BACKEND.parent / 'generate settings songs')
    parser.add_argument('--skip-seconds', type=float, default=10)
    args = parser.parse_args()
    if not np.isfinite(args.skip_seconds) or args.skip_seconds < 0:
        parser.error('--skip-seconds must be finite and non-negative')
    notes_path = BACKEND / 'audio_thresholds/technician_knob_observations.json'
    notes = json.loads(notes_path.read_text(encoding='utf-8'))
    recordings = []
    seen = set()
    for path in sorted(args.songs.glob('*.mp3'), key=lambda p: p.name.lower()):
        match = re.fullmatch(r'(pop|rnb|rock)\s*(\d+)', path.stem, re.I)
        if not match:
            continue
        genre = {'rnb': 'r&b'}.get(match[1].lower(), match[1].lower())
        number = int(match[2])
        if (genre, number) in seen or not 1 <= number <= 15:
            raise ValueError(f'Duplicate or unexpected song: {path.name}')
        seen.add((genre, number))
        samples, rate, decoding = load_audio(path)
        samples = samples[int(args.skip_seconds * rate):]
        if len(samples) < 10 * rate:
            raise ValueError(f'{path.name}: fewer than 10 seconds remain after trimming')
        with tempfile.TemporaryDirectory(prefix='karaok-calibration-') as temporary:
            audio_path = Path(temporary) / 'reference.wav'
            sf.write(audio_path, samples, rate, subtype='FLOAT')
            analysis = analyze_audio(audio_path)
        measurements = {key: float(analysis[section][field]) for key, (section, field) in FEATURE_PATHS.items()}
        if not all(np.isfinite(value) for value in measurements.values()):
            raise ValueError(f'Non-finite measurements: {path.name}')
        recordings.append(dict(recording_id=f'{genre}-{number:02}', genre=genre,
            file=path.name, sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
            skip_seconds=args.skip_seconds, analyzed_seconds=len(samples) / rate,
            measurements=measurements, decoding=decoding, knob_positions=notes['genres'][genre][number - 1]))
        print(f'Analyzed {path.name}', flush=True)
    if len(seen) != 45:
        raise ValueError('Expected exactly 15 songs for each of Pop, R&B and Rock')
    genres = {}
    for genre in ('pop', 'r&b', 'rock'):
        rows = [row for row in recordings if row['genre'] == genre]
        genres[genre] = dict(sample_count=15, corpus_status='unverified',
            metrics={key: target([row['measurements'][key] for row in rows], METRIC_UNITS[key]) for key in FEATURE_PATHS},
            knob_preferences={knob: target([row['knob_positions'][knob] for row in rows if row['knob_positions'][knob] is not None], 'knob_position', strict=False) for knob in ('bass', 'treble')})
    artifact = dict(schema_version=2, profile_version='2026.10.1-technician',
        generated_at='2026-10-16T00:00:00Z', generator_version='1.0.0',
        sources=dict(kind='technician_speaker_recordings',
            provenance='User-supplied speaker recordings and photographed technician notes; redistribution rights not established.',
            notes_sha256=hashlib.sha256(notes_path.read_bytes()).hexdigest(),
            calculation='Equal weight per song; linear p25/median/p75. Initial 10-second trim is an approximate calibration exclusion, not a detected settling point.',
            recordings=recordings), genres=genres)
    artifact['artifact_checksum'] = canonical_artifact_checksum(artifact)
    parse_genre_profile_artifact(artifact)
    output = BACKEND / 'audio_thresholds/genre_audio_profiles.json'
    output.write_text(json.dumps(artifact, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print(f'Wrote {output}', flush=True)


if __name__ == '__main__':
    main()
