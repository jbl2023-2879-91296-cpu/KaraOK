import copy
import json
import math
import tempfile
import unittest
from pathlib import Path

from audio_thresholds import load_thresholds, evaluate_features, classify_feature, score_feature
from audio_thresholds.artifact_integrity import canonical_artifact_checksum
from audio_thresholds.derive_median_thresholds import derive_median_profile
from audio_thresholds.derive_thresholds import load_good_cohort

# Full precision behind KaraOK Median.pdf: lower improvement, lower Good,
# fixed prior-Good median, upper Good, upper improvement.
EXPECTED = {
    'loudness': (-15.610895335, -12.670895335, -11.200895335, -9.730895335, -6.790895335),
    'bass': (16.70554435725, 52.70658229575, 70.707101265, 88.70762023425, 124.70865817275),
    'treble': (-1.1572309932, -0.2971793714, 0.1328464395, 0.5628722504, 1.4229238722),
    'sharpness': (-0.00306827395, -0.00052297665, 0.000749672, 0.00202232065, 0.00456761795),
    'flatness': (-0.000159873975, -0.000031791325, 0.00003225, 0.000096291325, 0.000224373975),
}

class MedianCenteredThresholdTests(unittest.TestCase):
    def test_generated_profile_is_reproducible_and_matches_pdf_counts(self):
        profile = load_thresholds()
        self.assertEqual(profile, derive_median_profile())
        cohort = load_good_cohort(Path(__file__).parent / 'fixtures/good_audio_results.csv')
        expected_counts = {'loudness': (27, 2, 1), 'bass': (26, 4, 0),
                           'treble': (26, 3, 1), 'sharpness': (26, 3, 1), 'flatness': (27, 2, 1)}
        for name, expected in expected_counts.items():
            statuses = [classify_feature(value, profile['metrics'][name]) for value in cohort.values[name]]
            self.assertEqual(tuple(statuses.count(status) for status in
                                   ('good', 'good_but_needs_improvement', 'bad')), expected)

    def test_weighted_overall_grade_anchors_are_preserved(self):
        profile = load_thresholds()
        for anchor, expected_score, status in [('center', 100, 'good'), ('good_lower', 80, 'good'),
                                             ('improvement_upper', 50, 'good_but_needs_improvement')]:
            values = {name: metric['assessment_bounds'][anchor] for name, metric in profile['metrics'].items()}
            result = evaluate_features(values)
            self.assertAlmostEqual(result['overall_score'], expected_score)
            self.assertEqual(result['overall_status'], status)

    def test_default_assessment_uses_pdf_boundaries_and_symmetric_scores(self):
        profile = load_thresholds()
        self.assertEqual(profile['quality_profile_version'], '2026.09.2-median')
        for name, expected in EXPECTED.items():
            with self.subTest(name=name):
                metric = profile['metrics'][name]
                bounds = metric['assessment_bounds']
                actual = [bounds[k] for k in ('improvement_lower', 'good_lower', 'center', 'good_upper', 'improvement_upper')]
                for value, target in zip(actual, expected):
                    self.assertAlmostEqual(value, target, places=12)
                low, gl, center, gu, high = actual
                for value, status, score in [(low, 'good_but_needs_improvement', 50), (gl, 'good', 80),
                                             (center, 'good', 100), (gu, 'good', 80),
                                             (high, 'good_but_needs_improvement', 50)]:
                    self.assertEqual(classify_feature(value, metric), status)
                    self.assertAlmostEqual(score_feature(value, metric), score)
                self.assertEqual(classify_feature(math.nextafter(gl, -math.inf), metric), 'good_but_needs_improvement')
                self.assertEqual(classify_feature(math.nextafter(gu, math.inf), metric), 'good_but_needs_improvement')
                self.assertEqual(classify_feature(math.nextafter(low, -math.inf), metric), 'bad')
                self.assertEqual(classify_feature(math.nextafter(high, math.inf), metric), 'bad')
                width = gu-gl
                self.assertAlmostEqual(score_feature(center-width/4, metric), score_feature(center+width/4, metric))
                self.assertAlmostEqual(score_feature(low-width, metric), 0)
                self.assertAlmostEqual(score_feature(high+width, metric), 0)

    def test_default_evaluation_changes_real_classifications(self):
        values = {name: bounds[2] for name, bounds in EXPECTED.items()}
        values['loudness'] = -15.93646911  # recording 23: formerly improvement
        result = evaluate_features(values)
        self.assertEqual(result['features']['loudness']['status'], 'bad')
        values['loudness'] = -10.34360594  # recording 20: formerly improvement
        self.assertEqual(evaluate_features(values)['features']['loudness']['status'], 'good')
        values['treble'] = 2.821164246
        self.assertEqual(evaluate_features(values)['features']['treble']['status'], 'bad')

    def test_reference_statistics_remain_unmodified_and_profiles_can_coexist(self):
        baseline = load_thresholds(Path(__file__).parents[1] / 'audio_thresholds/good_audio_thresholds.json')
        current = load_thresholds()
        self.assertNotEqual(current['quality_profile_version'], baseline['quality_profile_version'])
        for name, original in baseline['metrics'].items():
            actual = dict(current['metrics'][name])
            actual.pop('assessment_bounds')
            self.assertEqual(actual, original)
        self.assertEqual(current['overall'], baseline['overall'])

    def test_loader_rejects_resigned_invalid_assessment_bounds(self):
        original = load_thresholds()
        for invalid in (None, True, float('inf'), '1', -1000):
            payload = copy.deepcopy(original)
            payload['metrics']['bass']['assessment_bounds']['good_upper'] = invalid
            # Nonfinite values cannot even be checksummed; use JSON parser rejection.
            if invalid != float('inf'):
                payload['artifact_checksum'] = canonical_artifact_checksum(payload)
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'profile.json'
                path.write_text(json.dumps(payload), encoding='utf-8')
                with self.assertRaises(ValueError):
                    load_thresholds(path)
