"""Compare candidate spectral subtraction settings on required 20 dB recordings."""
import argparse
import csv
from pathlib import Path
from unittest.mock import patch

import librosa

from noise_guard_eval import HEADROOM, MUST_PASS_MNR, analyze_samples, compare, load_audio, run_case
from audio_engine import noise_guard


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clean", type=Path, required=True)
    parser.add_argument("--noise", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--settings", nargs="+", required=True, metavar="FLOOR:FACTOR")
    parser.add_argument("--shard", nargs=2, type=int, default=(0, 1), metavar=("INDEX", "COUNT"))
    args = parser.parse_args()
    index, count = args.shard
    if not 0 <= index < count:
        parser.error("Shard index must be between zero and the shard count minus one.")
    settings = []
    for setting in args.settings:
        try:
            floor, factor = map(float, setting.split(":"))
        except ValueError:
            parser.error("Settings must be FLOOR:FACTOR.")
        if not 0 <= floor <= 1 or not 1 <= factor < float("inf"):
            parser.error("Floor must be within [0, 1] and factor must be finite and at least 1.")
        settings.append((floor, factor))

    with args.baseline.open(newline="", encoding="utf-8") as source:
        rows = [row for row in csv.DictReader(source) if row["guard"] == "True"
                and row["mnr_db"] and float(row["mnr_db"]) in MUST_PASS_MNR.get(row["category"], ())]
    clean_names = sorted({row["clean"] for row in rows})[index::count]
    backgrounds = {name: load_audio(args.noise / name)[:2] for name in sorted({row["noise"] for row in rows})}
    original = noise_guard._subtract_noise
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="", encoding="utf-8") as output:
        writer = None
        for name in clean_names:
            song, sr, _ = load_audio(args.clean / name)
            song = song * HEADROOM
            references = {}
            for row in (row for row in rows if row["clean"] == name):
                noise, rate = backgrounds[row["noise"]]
                if rate != sr:
                    noise = librosa.resample(noise, orig_sr=rate, target_sr=sr)
                length = min(song.size, noise.size - 3 * sr)
                if length not in references:
                    references[length] = analyze_samples(song[:length], sr)
                for floor, factor in settings:
                    def subtract(audio, profile, _, frame_length, hop_length, *, sample_rate, high_band_factor):
                        return original(audio, profile, floor, frame_length, hop_length,
                                        sample_rate=sample_rate, high_band_factor=factor)

                    with patch.object(noise_guard, "_subtract_noise", subtract):
                        result = compare(references[length], run_case(song[:length], noise, sr, 20, True))
                    case = dict(clean=name, noise=row["noise"], category=row["category"],
                                floor=floor, factor=factor, before=row["passed"], after=result["passed"],
                                status_ok=result["status"]["ok"])
                    for metric, values in result["metrics"].items():
                        case[metric + "_before"] = row[metric + "_delta"]
                        case[metric + "_after"] = values["delta"]
                        case[metric + "_ok"] = values["ok"]
                    case["flatness_skipped"] = result["metrics"]["flatness"].get("skipped", False)
                    if writer is None:
                        writer = csv.DictWriter(output, fieldnames=case.keys())
                        writer.writeheader()
                    writer.writerow(case)
                    output.flush()


if __name__ == "__main__":
    main()
