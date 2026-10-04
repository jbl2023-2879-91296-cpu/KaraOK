"""Run with: python analyze_bad_samples.py

Uses backend/.venv when available, otherwise the current Python environment.
Dependencies can be installed with: python -m pip install -r backend/requirements.txt
Outputs: results_bad/results/<sample stem>/*_analysis.json and six PNGs,
plus results_bad/results/results.csv. Repeated runs append timestamped results.
Uses the current analyzer/settings; historical measurements may differ.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parent
EXTENSIONS = {".wav", ".mp3", ".flac", ".ogg"}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, default=ROOT / "audio sample(bad)")
    parser.add_argument("--dry-run", action="store_true", help="List inputs without analyzing")
    args = parser.parse_args(argv)
    source = args.input_dir.expanduser().resolve()
    if not source.is_dir():
        parser.error(f"Input directory does not exist: {source}")
    samples = sorted(
        (path for path in source.iterdir() if path.is_file() and path.suffix.lower() in EXTENSIONS),
        key=lambda path: path.name.casefold(),
    )
    if not samples:
        parser.error(f"No supported audio files found in: {source}")

    output = ROOT / "results_bad" / "results"
    candidates = [ROOT / "backend/.venv/Scripts/python.exe", ROOT / "backend/.venv/bin/python"]
    python = sys.executable
    for candidate in candidates:
        if candidate.is_file():
            try:
                probe = subprocess.run(
                    [str(candidate), "--version"], capture_output=True, timeout=10,
                )
            except (OSError, subprocess.TimeoutExpired):
                continue
            if probe.returncode == 0:
                python = str(candidate)
                break
    analyzer = ROOT / "backend/audio_analyzer.py"
    settings = ROOT / "backend/audio_analyzer_settings.json"
    print(f"Found {len(samples)} samples. Output: {output}", flush=True)
    print(f"Python: {python}", flush=True)
    if args.dry_run:
        for sample in samples:
            print(f"  {sample.name} -> {output / sample.stem}")
        return 0

    # Check dependencies once before starting a potentially long batch.
    environment = dict(os.environ, MPLBACKEND="Agg", PYTHONUNBUFFERED="1")
    check = subprocess.run(
        [python, str(analyzer), "--help"], cwd=ROOT, env=environment,
        capture_output=True, text=True, errors="replace",
    )
    if check.returncode:
        print(check.stderr, file=sys.stderr)
        print(
            f'Analyzer could not start. Install dependencies with:\n'
            f'"{python}" -m pip install -r "{ROOT / "backend/requirements.txt"}"',
            file=sys.stderr,
        )
        return 1

    import json

    behavior = json.loads(settings.read_text(encoding="utf-8"))["failure_behavior"]
    if not behavior["save_outputs_on_quality_failure"]:
        parser.error("Enable save_outputs_on_quality_failure in the analyzer settings first.")
    quality_exit = behavior["quality_failure_exit_code"]
    completed = quality_failed = 0
    failures: list[str] = []
    for index, sample in enumerate(samples, 1):
        print(f"\n[{index}/{len(samples)}] {sample.name}", flush=True)
        process = subprocess.run(
            [python, str(analyzer), str(sample), "--output-dir", str(output / sample.stem),
             "--settings", str(settings), "--save-json", "--save-csv", "--save-plots"],
            cwd=ROOT, env=environment,
        )
        if process.returncode == 130:
            return 130
        if process.returncode == 0:
            completed += 1
        elif process.returncode == quality_exit:
            completed += 1
            quality_failed += 1
        else:
            failures.append(sample.name)
            print(f"Technical failure (exit {process.returncode}); continuing.", flush=True)

    print(f"\nCompleted: {completed}/{len(samples)}; quality failures: {quality_failed}; "
          f"technical failures: {len(failures)}.")
    print(f"Outputs: {output}")
    for name in failures:
        print(f"  Failed: {name}")
    return 1 if failures else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nCancelled. Previously completed outputs are retained.", file=sys.stderr)
        raise SystemExit(130)
