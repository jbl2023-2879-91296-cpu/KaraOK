"""Promote a recorded phone measurement to the server calibration reference."""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import tempfile

BACKEND = Path(__file__).resolve().parents[1]
MEASUREMENTS = ("noise_floor_dbfs", "pink_lufs", "band_levels_db", "band_floor_db")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--measurement-id", required=True)
    parser.add_argument("--note", default="")
    parser.add_argument("--log", type=Path, default=(
        Path(os.environ.get("AUDIO_UPLOAD_DIR") or BACKEND / "uploads")
        / "calibration" / "measurements.jsonl"
    ))
    parser.add_argument("--out", type=Path, default=BACKEND / "audio_thresholds" / "mic_calibration_reference.json")
    args = parser.parse_args(argv)
    measurement = None
    if args.log.is_file():
        with args.log.open(encoding="utf-8") as log:
            for line in log:
                entry = json.loads(line)
                if entry.get("measurement_id") == args.measurement_id:
                    measurement = entry
                    break
    if measurement is None:
        print(f"Measurement {args.measurement_id} was not found in {args.log}.")
        return 1
    reference = {
        "version": 1,
        "reference_id": args.measurement_id,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "note": args.note,
        **{key: measurement[key] for key in MEASUREMENTS},
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", newline="\n", dir=args.out.parent, delete=False,
        ) as handle:
            temporary = Path(handle.name)
            json.dump(reference, handle, allow_nan=False, indent=2)
            handle.write("\n")
        temporary.chmod(0o644)
        temporary.replace(args.out)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    print(json.dumps(reference, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
