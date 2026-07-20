import json
import tempfile
import unittest
from pathlib import Path

from audio_thresholds import (
    BAD,
    GOOD,
    GOOD_BUT_NEEDS_IMPROVEMENT,
    NOT_EVALUATED,
    classify_feature,
    evaluate_features,
    load_thresholds,
    score_feature,
)
from audio_thresholds.derive_thresholds import (
    DEFAULT_BOOTSTRAP_SEED,
    derive_threshold_artifact,
    load_good_cohort,
    write_threshold_artifact,
)


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
RESULTS_CSV = REPOSITORY_ROOT / "results" / "results.csv"
THRESHOLD_JSON = (
    REPOSITORY_ROOT / "backend" / "audio_thresholds" / "good_audio_thresholds.json"
)


class GoodAudioThresholdTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.thresholds = load_thresholds(THRESHOLD_JSON)

    def test_current_csv_selects_thirty_unique_complete_recordings(self):
        cohort = load_good_cohort(RESULTS_CSV)

        self.assertEqual(len(cohort.rows), 30)
        self.assertEqual(cohort.summary["selected_recording_count"], 30)
        self.assertEqual(len(set(cohort.summary["recording_files"])), 30)
        self.assertEqual(cohort.summary["exclusions"]["invalid_or_non_finite_measurement"], 0)

    def test_expected_numpy_percentiles_are_preserved(self):
        artifact = derive_threshold_artifact(
            RESULTS_CSV,
            source_label="results/results.csv",
            bootstrap_iterations=200,
            bootstrap_seed=DEFAULT_BOOTSTRAP_SEED,
        )
        expected = {
            "loudness": (-13.4383603465, -11.200895335, -10.4977431775),
            "treble": (0.02381916105, 0.1328464395, 0.88387078285),
            "bass": (48.600903162, 70.707101265, 84.6019411005),
            "sharpness": (0.0003089165, 0.000749672, 0.0028542138),
            "flatness": (0.000005702, 0.00003225, 0.00013378465),
        }
        for key, (p05, median, p95) in expected.items():
            with self.subTest(metric=key):
                metric = artifact["metrics"][key]
                self.assertAlmostEqual(metric["p05"], p05, places=12)
                self.assertAlmostEqual(metric["median"], median, places=12)
                self.assertAlmostEqual(metric["p95"], p95, places=12)

    def test_classification_boundaries_are_inclusive(self):
        metric = self.thresholds["metrics"]["loudness"]

        self.assertEqual(classify_feature(metric["p05"], metric), GOOD)
        self.assertEqual(classify_feature(metric["p95"], metric), GOOD)
        self.assertEqual(
            classify_feature(metric["observed_min"], metric),
            GOOD_BUT_NEEDS_IMPROVEMENT,
        )
        self.assertEqual(
            classify_feature(metric["observed_max"], metric),
            GOOD_BUT_NEEDS_IMPROVEMENT,
        )
        self.assertEqual(classify_feature(metric["observed_min"] - 0.001, metric), BAD)
        self.assertEqual(classify_feature(metric["observed_max"] + 0.001, metric), BAD)
        self.assertEqual(classify_feature(float("nan"), metric), NOT_EVALUATED)

    def test_piecewise_score_has_exact_anchors_and_declines_outward(self):
        metric = self.thresholds["metrics"]["bass"]

        self.assertEqual(score_feature(metric["median"], metric), 100.0)
        self.assertEqual(score_feature(metric["p05"], metric), 80.0)
        self.assertEqual(score_feature(metric["p95"], metric), 80.0)
        self.assertEqual(score_feature(metric["observed_min"], metric), 50.0)
        self.assertEqual(score_feature(metric["observed_max"], metric), 50.0)
        self.assertLess(score_feature(metric["observed_min"] - 1.0, metric), 50.0)
        self.assertLess(score_feature(metric["observed_max"] + 1.0, metric), 50.0)
        self.assertLess(
            score_feature((metric["observed_min"] + metric["p05"]) / 2.0, metric),
            score_feature((metric["p05"] + metric["median"]) / 2.0, metric),
        )
        self.assertGreater(
            score_feature((metric["median"] + metric["p95"]) / 2.0, metric),
            score_feature((metric["p95"] + metric["observed_max"]) / 2.0, metric),
        )

    def test_weighted_overall_and_worst_feature_are_separate(self):
        medians = {
            key: metric["median"] for key, metric in self.thresholds["metrics"].items()
        }
        result = evaluate_features(medians, self.thresholds)
        self.assertEqual(result["overall_score"], 100.0)
        self.assertEqual(result["overall_status"], GOOD)
        self.assertEqual(result["worst_feature_status"], GOOD)

        medians["flatness"] = self.thresholds["metrics"]["flatness"]["observed_max"]
        result = evaluate_features(medians, self.thresholds)
        self.assertEqual(result["overall_score"], 95.0)
        self.assertEqual(result["overall_status"], GOOD)
        self.assertEqual(result["worst_feature_status"], GOOD_BUT_NEEDS_IMPROVEMENT)
        self.assertEqual(result["worst_features"], ["flatness"])

    def test_overall_status_uses_exact_weighted_score_boundaries(self):
        p05_values = {
            key: metric["p05"] for key, metric in self.thresholds["metrics"].items()
        }
        p05_result = evaluate_features(p05_values, self.thresholds)
        self.assertAlmostEqual(p05_result["overall_score"], 80.0)
        self.assertEqual(p05_result["overall_status"], GOOD)

        minimum_values = {
            key: metric["observed_min"]
            for key, metric in self.thresholds["metrics"].items()
        }
        minimum_result = evaluate_features(minimum_values, self.thresholds)
        self.assertAlmostEqual(minimum_result["overall_score"], 50.0)
        self.assertEqual(
            minimum_result["overall_status"], GOOD_BUT_NEEDS_IMPROVEMENT
        )

        zero_score_values = {}
        for key, metric in self.thresholds["metrics"].items():
            tail_width = max(
                metric["p05"] - metric["observed_min"],
                metric["median"] - metric["p05"],
            )
            zero_score_values[key] = metric["observed_min"] - tail_width
        zero_result = evaluate_features(zero_score_values, self.thresholds)
        self.assertAlmostEqual(zero_result["overall_score"], 0.0)
        self.assertEqual(zero_result["overall_status"], BAD)

    def test_all_features_are_required_and_weights_sum_to_one(self):
        weights = self.thresholds["overall"]["weights"]
        self.assertAlmostEqual(sum(weights.values()), 1.0)
        result = evaluate_features({"loudness": -11.2}, self.thresholds)
        self.assertEqual(result["overall_status"], NOT_EVALUATED)
        self.assertIn("bass", result["worst_features"])

    def test_derivation_is_deterministic_and_json_has_no_nan(self):
        first = derive_threshold_artifact(
            RESULTS_CSV,
            source_label="results/results.csv",
            bootstrap_iterations=200,
        )
        second = derive_threshold_artifact(
            RESULTS_CSV,
            source_label="results/results.csv",
            bootstrap_iterations=200,
        )
        self.assertEqual(first, second)

        with tempfile.TemporaryDirectory() as directory:
            output = write_threshold_artifact(first, Path(directory) / "thresholds.json")
            parsed = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(parsed, first)


if __name__ == "__main__":
    unittest.main()
