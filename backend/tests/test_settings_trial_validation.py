import csv
import json
import math
import tempfile
import unittest
from pathlib import Path

from scripts.validate_settings_trials import evaluate_trials, main


FIELDS = (
    "trial_id",
    "genre",
    "start_profile",
    "before_score",
    "after_score",
    "clipping_violation",
)


def trial(
    trial_id,
    before,
    after,
    *,
    genre="rock",
    start_profile="My Amplifier",
    clipping=False,
):
    return {
        "trial_id": trial_id,
        "genre": genre,
        "start_profile": start_profile,
        "before_score": before,
        "after_score": after,
        "clipping_violation": clipping,
    }


class SettingsTrialValidationTests(unittest.TestCase):
    def test_trial_report_requires_positive_median_majority_and_no_clipping(self):
        report = evaluate_trials(
            [
                trial("a", 70, 80),
                trial("b", 72, 75),
                trial("c", 80, 79),
            ]
        )

        self.assertEqual(
            set(report),
            {
                "trial_count",
                "median_score_change",
                "improved_count",
                "worsened_count",
                "unchanged_count",
                "clipping_violation_count",
                "passed",
            },
        )
        self.assertEqual(report["trial_count"], 3)
        self.assertEqual(report["median_score_change"], 3.0)
        self.assertEqual(report["improved_count"], 2)
        self.assertEqual(report["worsened_count"], 1)
        self.assertEqual(report["unchanged_count"], 0)
        self.assertEqual(report["clipping_violation_count"], 0)
        self.assertTrue(report["passed"])

    def test_any_clipping_violation_fails_release_gate(self):
        report = evaluate_trials([trial("a", 70, 80, clipping=True)])

        self.assertEqual(report["clipping_violation_count"], 1)
        self.assertFalse(report["passed"])

    def test_exactly_half_improved_does_not_pass(self):
        report = evaluate_trials(
            [
                trial("a", 70, 75),
                trial("b", 70, 74),
                trial("c", 70, 70),
                trial("d", 70, 69),
            ]
        )

        self.assertGreater(report["median_score_change"], 0)
        self.assertEqual(report["improved_count"], 2)
        self.assertFalse(report["passed"])

    def test_rejects_empty_duplicate_or_invalid_trials(self):
        invalid_cases = (
            ([], "at least one"),
            ([trial("a", 70, 80), trial("a", 72, 75)], "duplicate"),
            ([trial("a", 70, 80, genre="jazz")], "genre"),
            ([trial("a", math.nan, 80)], "finite"),
            ([trial("a", -1, 80)], "between 0 and 100"),
            ([trial("a", 70, 101)], "between 0 and 100"),
            ([trial("a", 70, 80, start_profile=" ")], "start_profile"),
            ([trial("a", 70, 80, clipping="yes")], "clipping_violation"),
        )
        for rows, message in invalid_cases:
            with self.subTest(message=message):
                with self.assertRaisesRegex(ValueError, message):
                    evaluate_trials(rows)

    def test_cli_writes_deterministic_json_report(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "trials.csv"
            first = root / "first.json"
            second = root / "second.json"
            with source.open("w", encoding="utf-8", newline="") as stream:
                writer = csv.DictWriter(stream, fieldnames=FIELDS)
                writer.writeheader()
                writer.writerow(trial("trial-2", 75, 76, genre="pop"))
                writer.writerow(trial("trial-1", 60, 68, genre="hip-hop"))

            self.assertEqual(main([str(source), "--output", str(first)]), 0)
            self.assertEqual(main([str(source), "--output", str(second)]), 0)

            self.assertEqual(first.read_bytes(), second.read_bytes())
            self.assertTrue(
                json.loads(first.read_text(encoding="utf-8"))["passed"]
            )

    def test_cli_rejects_incomplete_csv_columns(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "trials.csv"
            source.write_text("trial_id,genre\na,rock\n", encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "columns"):
                main([str(source), "--output", str(root / "report.json")])

    def test_cli_rejects_rows_with_extra_values(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "trials.csv"
            source.write_text(
                ",".join(FIELDS)
                + "\ntrial-a,rock,My Amplifier,70,80,false,unexpected\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(ValueError, "exactly six values"):
                main([str(source), "--output", str(root / "report.json")])


if __name__ == "__main__":
    unittest.main()
