"""Compare clean recordings with controlled mixtures of recorded background noise."""

import argparse
import csv
import sys
from collections import defaultdict
from pathlib import Path

import librosa

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

from audio_engine.analyzer import SUPPORTED_EXTENSIONS, load_audio
from audio_engine.noise_guard_eval import analyze_samples, compare, run_case


DEFAULT_CATEGORIES = {"jeep": "steady", "chicken": "transient",
                      "motorcycle": "transient", "human talk": "babble"}
HEADROOM = 0.25  # About -12 dB, before both reference analysis and mixing.
MUST_PASS_MNR = {"steady": {20, 10}, "transient": {20, 10}, "babble": {20}}


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

    args.out.mkdir(parents=True, exist_ok=True)
    grid = defaultdict(list)
    with (args.out / "cases.csv").open("w", newline="", encoding="utf-8") as output:
        writer = None
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
                        row = dict(clean=clean_path.name, noise=path.name, category=category,
                                   mnr_db=mnr, guard=guard, passed=result["passed"],
                                   confidence=case["noise_guard"]["confidence"])
                        for name, value in result["status"].items():
                            row[f"status_{name}"] = value
                        for name, metric in result["metrics"].items():
                            row[f"{name}_delta"] = metric["delta"]
                            row[f"{name}_ok"] = metric["ok"]
                        if writer is None:
                            writer = csv.DictWriter(output, fieldnames=list(row))
                            writer.writeheader()
                        writer.writerow(row)
                        grid[category, mnr, guard].append(result["passed"])

    lines = ["# Noise guard pass rates"]
    for guard in (False, True):
        lines.extend(["", f"## Guard {'on' if guard else 'off'}", "",
                      "| Noise type | " + " | ".join(f"{m:g} dB MNR" for m in args.mnr) + " |",
                      "|" + "---|" * (1 + len(args.mnr))])
        for category in grid_categories(noise[1] for noise in noises):
            cells = []
            for mnr in args.mnr:
                values = grid[category, mnr, guard]
                cell = f"{sum(values)}/{len(values)} ({sum(values)/len(values):.0%})" if values else "No cases"
                if guard and mnr in MUST_PASS_MNR.get(category, ()):
                    cell += " (must pass)"
                cells.append(cell)
            lines.append("| " + " | ".join([category, *cells]) + " |")
    (args.out / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

