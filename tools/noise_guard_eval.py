"""Compare clean recordings with controlled mixtures of recorded background noise."""

import argparse
import csv
import json
import sys
from collections import defaultdict
from pathlib import Path

import librosa
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

from audio_engine.analyzer import SUPPORTED_EXTENSIONS, load_audio
from audio_engine.noise_guard_eval import analyze_samples, compare, run_case


DEFAULT_CATEGORIES = {"jeep": "steady", "chicken": "transient",
                      "motorcycle": "transient", "human talk": "babble"}
HEADROOM = 0.25  # About -12 dB, before both reference analysis and mixing.
MUST_PASS_MNR = {"steady": {20}, "transient": {20}, "babble": {20}}
MUST_FLAG_MNR = {"steady": {10}, "transient": {10}}


def quiet_recording(clean, sr):
    """Add deterministic pink noise at -70 dBFS RMS in each recording segment."""
    preroll = 3 * sr
    rng = np.random.default_rng(20261118)
    white = rng.standard_normal(preroll + len(clean), dtype=np.float32)
    spectrum = np.fft.rfft(white)
    frequencies = np.fft.rfftfreq(len(white), 1 / sr)
    spectrum *= np.where(frequencies >= 20, 1 / np.sqrt(np.maximum(frequencies, 20)), 0)
    pink = np.fft.irfft(spectrum, len(white)).astype(np.float32)
    for segment in (pink[:preroll], pink[preroll:]):
        segment *= 10 ** (-70 / 20) / np.sqrt(np.mean(segment ** 2, dtype=np.float64))
    pink[preroll:] += clean
    return pink


def is_flagged(row):
    return row["confidence"] in ("low", "medium") and bool(row["warnings"])


def category_for(stem, overrides):
    for mapping in (overrides, DEFAULT_CATEGORIES):
        for name in sorted(mapping, key=len, reverse=True):
            if name in stem.casefold():
                return mapping[name]
    return None


def grid_categories(observed):
    categories = set(observed)
    standard = ["steady", "transient", "babble"]
    return [name for name in standard if name in categories] + sorted(categories.difference(standard))


def build_street_mix(noises):
    sources = {path.stem.casefold(): (audio, rate) for path, _, audio, rate in noises}
    if not DEFAULT_CATEGORIES.keys() <= sources.keys():
        return None

    recordings = [sources[name] for name in DEFAULT_CATEGORIES]
    mix_rate = max(rate for _, rate in recordings)
    aligned = [
        librosa.resample(audio, orig_sr=rate, target_sr=mix_rate) if rate != mix_rate else audio
        for audio, rate in recordings
    ]
    length = min(map(len, aligned))
    if not length:
        return None

    mix = np.zeros(length, dtype=np.float32)
    for audio in aligned:
        clip = audio[:length]
        rms = np.sqrt(np.mean(np.square(clip), dtype=np.float64))
        if rms == 0:
            return None
        mix += clip / rms
    return Path("street_mix"), "street_mix", mix, mix_rate


def confidence_summary(rows):
    """Evaluate confidence against the full tolerance result for guard-on rows."""
    enabled = [row for row in rows if row["guard"] and row["category"] != "quiet_room"]
    required_misses = [
        row for row in enabled
        if not row["passed"] and row["true_mnr_db"] in MUST_PASS_MNR.get(row["category"], ())
    ]
    low_mnr = [row for row in enabled if row["true_mnr_db"] == 5]
    passes = [row for row in enabled if row["passed"]]
    high_misses = sum(row["confidence"] == "high" for row in required_misses)
    low_at_5 = sum(row["confidence"] == "low" for row in low_mnr)
    high_passes = sum(row["confidence"] == "high" for row in passes)
    quiet = [row for row in rows if row["category"] == "quiet_room"]
    quiet_high = sum(row["confidence"] == "high" and not row["warnings"] for row in quiet)
    return [
        ("Required misses labelled high", high_misses, len(required_misses), "0", high_misses == 0),
        ("5 dB cases labelled low", low_at_5, len(low_mnr), "100%",
         bool(low_mnr) and low_at_5 == len(low_mnr)),
        ("Passing cases labelled high", high_passes, len(passes), "Report only", None),
        ("Quiet-room cases high with no noise warning", quiet_high, len(quiet), "100%",
         bool(quiet) and quiet_high == len(quiet)),
    ]


def format_summary(rows, levels, categories):
    grid = defaultdict(list)
    for row in rows:
        grid[row["category"], row["true_mnr_db"], row["guard"]].append(row["passed"])

    lines = ["# Noise guard pass rates", "", "Pass rates use matching status and all TOLERANCES."]
    categories = grid_categories(category for category in categories if category != "quiet_room")
    if "street_mix" in categories:
        lines.extend(["", "The report-only street mix combines the four tracks at equal RMS, "
                      "including the sum of their three-second noise checks."])
    for guard in (False, True):
        lines.extend(["", f"## Guard {'on' if guard else 'off'}", "",
                      "| Noise type | " + " | ".join(f"{m:g} dB MNR" for m in levels) + " |",
                      "|" + "---|" * (1 + len(levels))])
        for category in categories:
            cells = []
            for mnr in levels:
                values = grid[category, mnr, guard]
                cell = f"{sum(values)}/{len(values)} ({sum(values)/len(values):.0%})" if values else "No cases"
                if guard and mnr in MUST_PASS_MNR.get(category, ()):
                    cell += " (must pass)"
                cells.append(cell)
            lines.append("| " + " | ".join([category, *cells]) + " |")

    lines.extend(["", "## Confidence calibration (guard on)", "",
                  "| Check | Observed | Target | Met |", "|---|---:|---|---|"])
    for label, count, total, target, met in confidence_summary(rows):
        status = "—" if met is None else "Yes" if met else "No"
        lines.append(f"| {label} | {count}/{total} | {target} | {status} |")

    lines.extend(["", "## Required noise flagging (guard on)", "",
                  "| Noise type | MNR | Flagged | Labelled high | Target met |", "|---|---:|---:|---:|---|"])
    for category, mnrs in MUST_FLAG_MNR.items():
        for mnr in sorted(mnrs):
            cell = [row for row in rows if row["guard"] and row["category"] == category and row["true_mnr_db"] == mnr]
            flagged = sum(map(is_flagged, cell))
            high = sum(row["confidence"] == "high" for row in cell)
            met = bool(cell) and 10 * flagged >= 9 * len(cell) and high == 0
            lines.append(f"| {category} | {mnr:g} dB | {flagged}/{len(cell)} | {high} | {'Yes' if met else 'No'} |")

    lines.extend(["", "## Quiet room (−70 dBFS pink noise)", "",
                  "| Song | Confidence | Measured MNR | Usable | Dropped | Warnings |",
                  "|---|---|---:|---:|---:|---|"])
    for row in rows:
        if row["category"] == "quiet_room":
            mnr = row["measured_mnr_db"]
            measured = f"{mnr:.2f} dB" if mnr is not None else "—"
            warnings = ", ".join(row["warnings"]) or "—"
            lines.append(f"| {row['clean']} | {row['confidence']} | {measured} | {row['usable_percentage']:.2f}% | "
                         f"{row['dropped_percentage']:.2f}% | {warnings} |")
    return "\n".join(lines) + "\n"


def evaluation_row(clean, noise, category, mnr, guard, case, result=None):
    report = case["noise_guard"]
    row = dict(clean=clean, noise=noise, category=category, mnr_db=mnr, guard=guard,
               passed=result["passed"] if result else None,
               confidence=report["confidence"], true_mnr_db=mnr,
               measured_mnr_db=report["music_to_noise_db"],
               preroll_noise_dbfs=report["preroll_noise_dbfs"],
               subtraction_applied=report["subtraction_applied"],
               usable_percentage=report["usable_percentage"],
               dropped_percentage=report["transient_frames_removed_percentage"],
               warnings=report["warnings"])
    row["flagged"] = is_flagged(row)
    status = result["status"] if result else dict(clean=None, noisy=None, ok=None)
    for name, value in status.items():
        row[f"status_{name}"] = value
    metrics = result["metrics"] if result else dict.fromkeys(
        ("loudness", "bass", "treble", "sharpness", "flatness", "score"), dict(delta=None, ok=None)
    )
    for name, metric in metrics.items():
        row[f"{name}_delta"] = metric["delta"]
        row[f"{name}_ok"] = metric["ok"]
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clean", required=True, type=Path)
    parser.add_argument("--noise", required=True, type=Path)
    parser.add_argument("--mnr", nargs="+", type=float, default=[20, 10, 5])
    parser.add_argument("--limit", type=int, default=10)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--category", nargs="+", metavar="NAME=CATEGORY", default=[])
    args = parser.parse_args()
    categories = {}
    for entry in args.category:
        name, sep, category = entry.partition("=")
        if not sep or not name or not category:
            parser.error(f"Expected NAME=CATEGORY, got {entry!r}")
        categories[name.casefold()] = category

    clean_paths = sorted(p for p in args.clean.iterdir() if p.suffix.lower() in SUPPORTED_EXTENSIONS)
    noises = []
    for path in sorted(args.noise.iterdir()):
        if path.suffix.lower() in {".wav", ".mp3"}:
            category = category_for(path.stem, categories)
            if category is None:
                parser.error(f"Supply --category for {path.name}")
            noise, rate, _ = load_audio(path)
            noises.append((path, category, noise, rate))
    if not clean_paths or not noises or args.limit < 1:
        parser.error("At least one clean and noise file and a positive limit are required.")
    street_mix = build_street_mix(noises)
    if street_mix is not None:
        noises.append(street_mix)

    args.out.mkdir(parents=True, exist_ok=True)
    rows = []
    with (args.out / "cases.csv").open("w", newline="", encoding="utf-8") as output:
        writer = None

        def save(row):
            nonlocal writer
            if writer is None:
                writer = csv.DictWriter(output, fieldnames=list(row))
                writer.writeheader()
            writer.writerow(dict(row, warnings=json.dumps(row["warnings"], ensure_ascii=False)))
            rows.append(row)

        for clean_path in clean_paths[:args.limit]:
            clean, sr, _ = load_audio(clean_path)
            clean = clean * HEADROOM
            references = {}
            for path, category, noise, rate in noises:
                background = librosa.resample(noise, orig_sr=rate, target_sr=sr) if rate != sr else noise
                length = min(len(clean), len(background) - 3 * sr)
                if length < 10 * sr:
                    print(
                        f"Warning: skipping {clean_path.name} and {path.name}: less than 10 s of song.",
                        file=sys.stderr,
                    )
                    continue
                if length not in references:
                    references[length] = analyze_samples(clean[:length], sr)
                for mnr in args.mnr:
                    for guard in (False, True):
                        case = run_case(clean[:length], background, sr, mnr, guard)
                        result = compare(references[length], case)
                        save(evaluation_row(clean_path.name, path.name, category, mnr, guard, case, result))
            if clean.size >= 10 * sr:
                quiet = analyze_samples(quiet_recording(clean, sr), sr, preroll=3.0)
                save(evaluation_row(clean_path.name, "pink_noise", "quiet_room", None, True, quiet))
            output.flush()

    (args.out / "summary.md").write_text(
        format_summary(rows, args.mnr, (noise[1] for noise in noises)), encoding="utf-8"
    )


if __name__ == "__main__":
    main()

