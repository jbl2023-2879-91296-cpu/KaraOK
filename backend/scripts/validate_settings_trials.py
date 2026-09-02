"""Validate controlled amplifier-setting trials against the release gate."""

from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
import sys
from collections.abc import Iterable, Mapping, Sequence
from pathlib import Path
from typing import Any


BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from audio_thresholds import load_genre_profiles, normalize_genre  # noqa: E402


CSV_FIELDS = (
    "trial_id",
    "genre",
    "start_profile",
    "before_score",
    "after_score",
    "clipping_violation",
)


def _required_text(value: Any, name: str, row_number: int) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"Row {row_number} requires a non-empty {name}")
    return value.strip()


def _score(value: Any, name: str, row_number: int) -> float:
    if isinstance(value, bool):
        raise ValueError(f"Row {row_number} {name} must be a finite number")
    try:
        number = float(value)
    except (TypeError, ValueError) as error:
        raise ValueError(
            f"Row {row_number} {name} must be a finite number"
        ) from error
    if not math.isfinite(number):
        raise ValueError(f"Row {row_number} {name} must be a finite number")
    if not 0 <= number <= 100:
        raise ValueError(f"Row {row_number} {name} must be between 0 and 100")
    return number


def _boolean(value: Any, name: str, row_number: int) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, int) and value in (0, 1):
        return bool(value)
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"true", "1"}:
            return True
        if normalized in {"false", "0"}:
            return False
    raise ValueError(f"Row {row_number} {name} must be true or false")


def _validated_trial(
    row: Mapping[str, Any],
    row_number: int,
    enabled_genres: frozenset[str],
) -> dict[str, Any]:
    missing = set(CSV_FIELDS).difference(row)
    if missing:
        raise ValueError(
            f"Row {row_number} is missing required columns: {', '.join(sorted(missing))}"
        )
    trial_id = _required_text(row["trial_id"], "trial_id", row_number)
    raw_genre = _required_text(row["genre"], "genre", row_number)
    try:
        genre = normalize_genre(raw_genre)
    except ValueError as error:
        raise ValueError(f"Row {row_number} has unsupported genre {raw_genre!r}") from error
    if genre not in enabled_genres:
        raise ValueError(f"Row {row_number} has unsupported genre {raw_genre!r}")
    return {
        "trial_id": trial_id,
        "genre": genre,
        "start_profile": _required_text(
            row["start_profile"], "start_profile", row_number
        ),
        "before_score": _score(row["before_score"], "before_score", row_number),
        "after_score": _score(row["after_score"], "after_score", row_number),
        "clipping_violation": _boolean(
            row["clipping_violation"], "clipping_violation", row_number
        ),
    }


def evaluate_trials(trials: Iterable[Mapping[str, Any]]) -> dict[str, Any]:
    """Return the deterministic release-gate report for controlled trials."""

    enabled_genres = frozenset(load_genre_profiles().genres)
    validated: list[dict[str, Any]] = []
    trial_ids: set[str] = set()
    for row_number, row in enumerate(trials, start=1):
        if not isinstance(row, Mapping):
            raise ValueError(f"Row {row_number} must be a mapping")
        trial = _validated_trial(row, row_number, enabled_genres)
        trial_id = trial["trial_id"]
        if trial_id in trial_ids:
            raise ValueError(f"Row {row_number} has duplicate trial_id {trial_id!r}")
        trial_ids.add(trial_id)
        validated.append(trial)

    if not validated:
        raise ValueError("Controlled trial input must contain at least one row")

    changes = [
        round(trial["after_score"] - trial["before_score"], 6)
        for trial in validated
    ]
    changes = [
        0.0 if math.isclose(change, 0.0, abs_tol=1e-9) else change
        for change in changes
    ]
    improved = sum(change > 0 for change in changes)
    worsened = sum(change < 0 for change in changes)
    unchanged = len(changes) - improved - worsened
    clipping = sum(trial["clipping_violation"] for trial in validated)
    median_change = round(float(statistics.median(changes)), 6)
    passed = (
        median_change > 0
        and improved > len(validated) / 2
        and improved > worsened
        and clipping == 0
    )
    return {
        "trial_count": len(validated),
        "median_score_change": median_change,
        "improved_count": improved,
        "worsened_count": worsened,
        "unchanged_count": unchanged,
        "clipping_violation_count": clipping,
        "passed": passed,
    }


def _read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        fields = reader.fieldnames
        if (
            fields is None
            or len(fields) != len(CSV_FIELDS)
            or set(fields) != set(CSV_FIELDS)
        ):
            raise ValueError(
                "CSV columns must be exactly: " + ", ".join(CSV_FIELDS)
            )
        rows = list(reader)
        if any(None in row for row in rows):
            raise ValueError("CSV rows must contain exactly six values")
        return rows


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate controlled KaraOK amplifier-setting trials."
    )
    parser.add_argument("csv_path", type=Path, help="Controlled-trial CSV input")
    parser.add_argument("--output", required=True, type=Path, help="JSON report path")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    report = evaluate_trials(_read_csv(args.csv_path))
    encoded = json.dumps(
        report,
        indent=2,
        sort_keys=True,
        allow_nan=False,
    ) + "\n"
    args.output.write_text(encoded, encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2) from error
