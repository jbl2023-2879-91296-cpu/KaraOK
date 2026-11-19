"""Regenerate a Noise Guard before/after report from two evaluation CSV files."""

import argparse
import csv
from pathlib import Path

from noise_guard_eval import MUST_PASS_MNR


def read_cases(path):
    with path.open(newline="", encoding="utf-8") as source:
        rows = list(csv.DictReader(source))
    cases = {(r["clean"], r["noise"], r["category"], float(r["mnr_db"]), r["guard"]): r for r in rows if r["mnr_db"]}
    if len(cases) != sum(bool(row["mnr_db"]) for row in rows):
        raise ValueError(f"Duplicate cases in {path}")
    return cases


def high_confidence_misses(cases):
    misses = [row for (_, _, category, mnr, guard), row in cases.items()
              if guard == "True" and mnr in MUST_PASS_MNR.get(category, ()) and row["passed"] == "False"]
    return f"{sum(row['confidence'] == 'high' for row in misses)}/{len(misses)}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    before, after = read_cases(args.before), read_cases(args.after)
    if not before.keys() <= after.keys():
        parser.error("All baseline cases must also appear in the later evaluation.")

    lines = [
        "# Noise Guard comparison", "",
        "Pass rates use the status and tolerance policy recorded by each evaluation.", "",
        "| Noise type | MNR | Guard | Original | Tuned |",
        "|---|---:|---|---:|---:|",
    ]
    for category, mnr, guard in sorted({key[2:] for key in after}):
        keys = [key for key in after if key[2:] == (category, mnr, guard)]
        reference = [before[key] for key in keys if key in before]
        original = f"{sum(row['passed'] == 'True' for row in reference)}/{len(reference)}" if reference else "N/A"
        current = sum(after[key]["passed"] == "True" for key in keys)
        required = " (required)" if mnr in MUST_PASS_MNR.get(category, ()) else ""
        lines.append(f"| {category} | {mnr:g} dB{required} | {'On' if guard == 'True' else 'Off'} | "
                     f"{original} | {current}/{len(keys)} |")
    lines.extend(["", f"Required misses labelled high: {high_confidence_misses(before)} before, "
                  f"{high_confidence_misses(after)} after."])
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
