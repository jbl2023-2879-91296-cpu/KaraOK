"""Diagnostic only: isolate the limit of power subtraction with aligned noise."""
import argparse
import csv
from pathlib import Path
from collections import Counter
from statistics import median
from unittest.mock import patch

from noise_guard_eval import HEADROOM, MUST_FLAG_MNR, run_case

import librosa
import numpy as np
from audio_engine import noise_guard
from audio_engine.analyzer import load_audio
from audio_engine.noise_guard_eval import analyze_samples, compare

MNR = 10


def oracle_subtractor(aligned_noise, time_varying, calls):
    def subtract(song, noise_profile, floor, frame_length, hop_length):
        calls.append(True)
        assert song.shape == aligned_noise.shape
        transform = dict(n_fft=frame_length, hop_length=hop_length, window="hann", center=True)
        mixture_spectrum = librosa.stft(song, **transform)
        noise_power = np.abs(librosa.stft(aligned_noise, **transform)) ** 2
        if not time_varying:
            noise_power = noise_power.mean(axis=1, keepdims=True)
        mixture_power = np.maximum(np.abs(mixture_spectrum) ** 2, noise_guard._EPS)
        gain = np.sqrt(np.maximum(1 - noise_power / mixture_power, floor ** 2))
        return librosa.istft(mixture_spectrum * gain, length=song.size, **transform)

    return subtract


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--clean", required=True, type=Path)
    parser.add_argument("--noise", required=True, type=Path)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    with args.baseline.open(newline="", encoding="utf-8") as source:
        baseline = {
            (r["clean"], r["noise"]): r for r in csv.DictReader(source)
            if r["guard"] == "True" and r["mnr_db"] and float(r["mnr_db"]) == MNR
            and MNR in MUST_FLAG_MNR.get(r["category"], ())
        }
    if not baseline:
        parser.error("The baseline must contain guard-on required 10 dB cases.")
    clean_paths = [args.clean / name for name in sorted({key[0] for key in baseline})]
    noises = {name: load_audio(args.noise / name)[:2] for name in sorted({key[1] for key in baseline})}
    args.out.mkdir(parents=True, exist_ok=True)
    rows = []
    with (args.out / "cases.csv").open("w", newline="", encoding="utf-8") as output:
        writer = None
        for clean_path in clean_paths:
            original, sr, _ = load_audio(clean_path)
            original = original * HEADROOM
            references = {}
            for name, (noise, rate) in noises.items():
                if (clean_path.name, name) not in baseline:
                    continue
                if sr != rate:
                    noise = librosa.resample(noise, orig_sr=rate, target_sr=sr)
                length = min(len(original), len(noise) - 3 * sr)
                assert length >= 10 * sr
                clean = original[:length]
                noise_during_song = noise[3 * sr : 3 * sr + length]
                gain = np.linalg.norm(clean) / np.linalg.norm(noise_during_song) * 10 ** (-MNR / 20)
                aligned_noise = noise_during_song * gain
                if length not in references:
                    references[length] = analyze_samples(clean, sr)
                reference = references[length]
                for mode, time_varying in (("song_average", False), ("frame_aligned", True)):
                    calls = []
                    with patch.object(noise_guard, "_subtract_noise", oracle_subtractor(aligned_noise, time_varying, calls)):
                        measured = run_case(clean, noise, sr, MNR, True)
                    assert len(calls) == 1, (clean_path.name, name, mode)
                    result = compare(reference, measured)
                    row = dict(clean=clean_path.name, noise=name, mode=mode, passed=result["passed"],
                               status_ok=result["status"]["ok"], kept=measured["noise_guard"]["usable_percentage"])
                    for metric, values in result["metrics"].items():
                        row[f"{metric}_delta"] = values["delta"]
                        row[f"{metric}_ok"] = values["ok"]
                    if writer is None:
                        writer = csv.DictWriter(output, fieldnames=list(row))
                        writer.writeheader()
                    writer.writerow(row)
                    rows.append(row)
                    output.flush()
                    print(clean_path.name, name, mode, f"bass drift {row['bass_delta']:+.2f} pp", flush=True)
    summarize(args.out, baseline, rows)


def summarize(destination, baseline, rows):
    modes = {
        name: {(r["clean"], r["noise"]): r for r in rows if r["mode"] == name}
        for name in ("song_average", "frame_aligned")
    }
    if any(mode.keys() != baseline.keys() for mode in modes.values()):
        raise ValueError("Both noise profiles must cover every baseline case.")

    def count(group, field):
        return sum(str(row[field]) == "True" for row in group)

    lines = [
        "# Noise Guard isolated-noise diagnostic",
        "",
        f"The {len(baseline)} required 10 dB mixtures use the same clean clips, input headroom, "
        "acoustic noise tracks, production scoring, transient gating, and tolerances as the supplied baseline. "
        "The diagnostic filters use the isolated noise track's song-average or frame-aligned power spectrum. "
        "Both retain the mixture phase and existing power-subtraction formula. Full passes use all TOLERANCES.",
        "",
        "## Bass within 3 percentage points",
        "",
        "| Noise track | Current | True song-average spectrum | True frame-aligned spectrum |",
        "|---|---:|---:|---:|",
    ]
    sources = (*sorted({key[1] for key in baseline}), "All")
    for source in sources:
        keys = [k for k in baseline if source in ("All", k[1])]
        cells = [f"{count([group[k] for k in keys], 'bass_ok')}/{len(keys)}"
                 for group in (baseline, *modes.values())]
        lines.append("| " + " | ".join((source, *cells)) + " |")
    lines.extend(["", f"## Comparison across all {len(baseline)} cases", "",
                  "| Mode | Full tolerance passes | Bass misses recovered | Median absolute bass drift |",
                  "|---|---:|---:|---:|"])
    bass_misses = {k for k, r in baseline.items() if r["bass_ok"] == "False"}
    for label, group in (("Current guard", baseline), ("Song-average spectrum", modes["song_average"]), ("Frame-aligned spectrum", modes["frame_aligned"])):
        passes = count(group.values(), "passed")
        recovered = count([group[k] for k in bass_misses], "bass_ok")
        drift = median(abs(float(r["bass_delta"])) for r in group.values() if r["bass_delta"] not in ("", None))
        lines.append(f"| {label} | {passes}/{len(group)} | {recovered}/{len(bass_misses)} | {drift:.2f} pp |")
    for name, group in modes.items():
        failed = Counter(field for r in group.values() for field, value in r.items()
                         if field.endswith("_ok") and str(value) == "False")
        lines.extend(["", f"{name} misses by check: " + ", ".join(f"{field.removesuffix('_ok')} {n}" for field, n in failed.most_common()) + "."])
    lines.append("")
    summary = "\n".join(lines)
    (destination / "summary.md").write_text(summary, encoding="utf-8")
    print(summary)


if __name__ == "__main__":
    main()
