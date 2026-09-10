import hashlib
import json
import unittest
from unittest.mock import patch
import tempfile
from contextlib import contextmanager
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
from audio_thresholds.artifact_integrity import canonical_artifact_checksum


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
RESULTS_CSV = Path(__file__).resolve().parent / "fixtures" / "good_audio_results.csv"
THRESHOLD_JSON = (
    REPOSITORY_ROOT / "backend" / "audio_thresholds" / "good_audio_thresholds.json"
)


@contextmanager
def temporary_threshold_path():
    # Service accounts can read the release checkout without owning it.
    # tempfile honors TMPDIR, including the deployment test cache directory.
    with tempfile.TemporaryDirectory(prefix="karaok-threshold-") as directory:
        yield Path(directory) / "threshold.json"


class GoodAudioThresholdTests(unittest.TestCase):
    def test_temporary_artifact_works_with_read_only_checkout(self):
        original_write = Path.write_text
        source_directory = Path(__file__).resolve().parent

        def reject_source_write(path, *args, **kwargs):
            if path.is_relative_to(source_directory):
                raise PermissionError("The service account cannot write to the checkout")
            return original_write(path, *args, **kwargs)

        with tempfile.TemporaryDirectory() as scratch:
            with patch.object(tempfile, "tempdir", scratch):
                with patch.object(Path, "write_text", reject_source_write):
                    with temporary_threshold_path() as artifact:
                        artifact.write_text("{}", encoding="utf-8")
                        self.assertEqual(artifact.read_text(encoding="utf-8"), "{}")
                        self.assertTrue(artifact.is_relative_to(Path(scratch)))
                    self.assertFalse(artifact.exists())
                self.assertEqual(list(Path(scratch).iterdir()), [])

    @classmethod
    def setUpClass(cls):
        cls.thresholds = load_thresholds(THRESHOLD_JSON)

    def test_current_csv_selects_thirty_unique_complete_recordings(self):
        self.assertEqual(
            hashlib.sha256(RESULTS_CSV.read_bytes()).hexdigest(),
            "bcc5d4c2710f1d49572a17db56c5cc23ff5e8161f17adc9d2486b0edc8adfaa5",
        )
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

        with temporary_threshold_path() as path:
            output = write_threshold_artifact(first, path)
            parsed = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(parsed, first)

    def test_empirical_artifact_has_version_and_canonical_checksum(self):
        artifact = derive_threshold_artifact(
            RESULTS_CSV,
            source_label="results/results.csv",
            bootstrap_iterations=200,
        )
        self.assertEqual(artifact["quality_profile_version"], "2026.09.1")
        checksum = artifact["artifact_checksum"]
        unsigned = dict(artifact)
        unsigned.pop("artifact_checksum")
        canonical = json.dumps(
            unsigned, sort_keys=True, separators=(",", ":"), allow_nan=False
        )
        self.assertEqual(
            checksum,
            hashlib.sha256(canonical.encode("utf-8")).hexdigest(),
        )

    def test_loader_rejects_tampered_empirical_artifact(self):
        payload = json.loads(THRESHOLD_JSON.read_text(encoding="utf-8"))
        payload["metrics"]["bass"]["median"] += 1
        with temporary_threshold_path() as path:
            path.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "checksum"):
                load_thresholds(path)

    def _assert_schema_mutation_rejected(self, path, key, value=None, *, remove=False):
        payload = json.loads(THRESHOLD_JSON.read_text(encoding="utf-8"))
        target = payload
        for part in path:
            target = target[part]
        if remove:
            del target[key]
        else:
            target[key] = value
        payload["artifact_checksum"] = canonical_artifact_checksum(payload)
        with temporary_threshold_path() as artifact_path:
            artifact_path.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaises(ValueError):
                load_thresholds(artifact_path)

    def test_loader_rejects_unknown_and_missing_fields_at_authoritative_levels(self):
        levels = (
            ((), "unexpected", False),
            ((), "purpose", True),
            (("source",), "unexpected", False),
            (("source",), "path", True),
            (("cohort",), "unexpected", False),
            (("cohort",), "source_row_count", True),
            (("cohort", "exclusions"), "unexpected", False),
            (("cohort", "exclusions"), "not_completed", True),
            (("derivation",), "unexpected", False),
            (("derivation",), "library", True),
            (("classification",), "unexpected", False),
            (("classification",), "good", True),
            (("scoring",), "unexpected", False),
            (("scoring",), "range", True),
            (("scoring", "anchors"), "unexpected", False),
            (("scoring", "anchors"), "median", True),
            (("overall",), "unexpected", False),
            (("overall",), "ranked_features", True),
            (("overall", "weights"), "unexpected", False),
            (("overall", "weights"), "bass", True),
            (("overall", "status_rules"), "unexpected", False),
            (("overall", "status_rules"), "bad", True),
            (("metrics",), "unexpected", False),
            (("metrics",), "bass", True),
            (("metrics", "bass"), "unexpected", False),
            (("metrics", "bass"), "unit", True),
            (("metrics", "bass", "bootstrap_95_ci"), "unexpected", False),
            (("metrics", "bass", "bootstrap_95_ci"), "median", True),
            (("spearman_correlations",), "unexpected", False),
            (("spearman_correlations",), "bass", True),
            (("spearman_correlations", "bass"), "unexpected", False),
            (("spearman_correlations", "bass"), "treble", True),
            (("recovery_sensitivity",), "unexpected", False),
            (("recovery_sensitivity",), "strict_rule", True),
            (("recovery_sensitivity", "metrics"), "unexpected", False),
            (("recovery_sensitivity", "metrics"), "bass", True),
            (("recovery_sensitivity", "metrics", "bass"), "unexpected", False),
            (("recovery_sensitivity", "metrics", "bass"), "strict_p05", True),
        )
        for path, key, remove in levels:
            with self.subTest(path=".".join(path), key=key, remove=remove):
                self._assert_schema_mutation_rejected(
                    path,
                    key,
                    "unexpected",
                    remove=remove,
                )

    def test_loader_rejects_invalid_empirical_evidence_anchors_and_units(self):
        mutations = (
            (("source",), "sha256", "not-a-sha256"),
            (("classification",), "good", "value looks nice"),
            (("scoring",), "range", [0.0, 99.0]),
            (("scoring", "anchors"), "median", 99.0),
            (
                ("overall",),
                "ranked_features",
                ["bass", "loudness", "treble", "sharpness", "flatness"],
            ),
            (("overall", "status_rules"), "good", "overall_score >= 75"),
            (("metrics", "bass"), "csv_column", "wrong.column"),
            (("metrics", "bass"), "unit", "ratio"),
            (("metrics", "bass"), "rank", 3),
            (("metrics", "bass"), "sample_count", 29),
        )
        for path, key, value in mutations:
            with self.subTest(path=".".join(path), key=key, value=value):
                self._assert_schema_mutation_rejected(path, key, value)

    def test_loader_rejects_coerced_and_non_finite_empirical_numbers(self):
        mutations = (
            ((), "schema_version", 1.0),
            (("cohort",), "selected_recording_count", "30"),
            (("derivation",), "bootstrap_iterations", 10000.0),
            (("overall", "weights"), "bass", "0.25"),
            (("metrics", "bass"), "sample_count", True),
            (("metrics", "bass"), "median", "70.7"),
            (("metrics", "bass"), "median", "NaN"),
            (("metrics", "bass", "bootstrap_95_ci"), "median", ["NaN", 80.0]),
            (("spearman_correlations", "bass"), "treble", "-0.18"),
            (("recovery_sensitivity",), "strict_sample_count", 29.0),
            (("recovery_sensitivity", "metrics", "bass"), "strict_p05", "Infinity"),
        )
        for path, key, value in mutations:
            with self.subTest(path=".".join(path), key=key, value=value):
                self._assert_schema_mutation_rejected(path, key, value)

    def test_loader_rejects_unknown_status_counts_and_algorithm_version(self):
        mutations = (
            (
                ("cohort",),
                "quality_status_counts",
                {"passed": 3, "warning": 26, "invented": 1},
            ),
            (
                ("cohort",),
                "decode_status_counts",
                {"complete": 4, "recovered_partial": 25, "invented": 1},
            ),
            ((), "algorithm_version", "9.9.9"),
        )
        for path, key, value in mutations:
            with self.subTest(path=".".join(path), key=key):
                self._assert_schema_mutation_rejected(path, key, value)

    def test_loader_rejects_changed_recovery_rule_and_false_deltas(self):
        self._assert_schema_mutation_rejected(
            ("recovery_sensitivity",),
            "strict_rule",
            "decode_status is complete",
        )
        for false_delta in (0.001, 1e-13):
            with self.subTest(false_delta=false_delta):
                payload = json.loads(THRESHOLD_JSON.read_text(encoding="utf-8"))
                recovery_metric = payload["recovery_sensitivity"]["metrics"]["bass"]
                recovery_metric["p05_delta_from_full"] += false_delta
                payload["artifact_checksum"] = canonical_artifact_checksum(payload)
                with temporary_threshold_path() as artifact_path:
                    artifact_path.write_text(json.dumps(payload), encoding="utf-8")
                    with self.assertRaises(ValueError):
                        load_thresholds(artifact_path)

    def test_loader_rejects_empty_limitations(self):
        self._assert_schema_mutation_rejected((), "limitations", [])

    def test_loader_rejects_noncanonical_cohort_utc_timestamp(self):
        for timestamp in (
            "2026-07-19T10:16:41.122103Z",
            "2026-07-19t10:16:41.122103+00:00",
            "2026-02-30T10:16:41.122103+00:00",
        ):
            with self.subTest(timestamp=timestamp):
                self._assert_schema_mutation_rejected(
                    ("cohort",), "latest_analyzed_at_utc", timestamp
                )


if __name__ == "__main__":
    unittest.main()
