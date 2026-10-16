import unittest
from dataclasses import replace

from test_settings_recommendation_engine import profile, request
from audio_thresholds.genre_profiles import MetricTarget, load_genre_profiles, parse_genre_profile_artifact
from audio_thresholds.artifact_integrity import canonical_artifact_checksum
from settings_recommendations import AmplifierScale, KnobSettings, SafetySignals, generate_recommendation
from karaok.core.thresholds.genre_scoring import score_genre_values
from karaok.audio_pipeline.summary import apply_genre_evaluation, summarize_audio_analysis


class TechnicianCalibrationTests(unittest.TestCase):
    def setUp(self):
        self.profile = replace(profile(), knob_preferences={
            'bass': MetricTarget(-6, -4, -2, 4, 'knob_position'),
            'treble': MetricTarget(2, 4, 6, 4, 'knob_position'),
        })

    def recommend(self, bass, *, current=4, verification=False):
        return generate_recommendation(request(
            scale=AmplifierScale(-10, 10, .5),
            current=KnobSettings(0, current, 0, 0, 0),
            measurements=dict(loudness=0, bass=bass, treble=40, sharpness=0, flatness=80),
            verification=verification), self.profile)

    def test_high_bass_decreases_and_other_controls_remain_unchanged(self):
        result = self.recommend(80)
        self.assertEqual(result.adjustments['bass'].recommended, 2)
        self.assertEqual(result.adjustments['bass'].reason_code, 'above_genre_range')
        self.assertGreater(result.adjustments['volume'].delta, 0)
        for knob in ('treble', 'sharpness', 'flatness'):
            self.assertEqual(result.adjustments[knob].delta, 0)

    def test_low_bass_increases_even_when_technician_median_is_lower(self):
        self.assertGreater(self.recommend(0).adjustments['bass'].recommended, 4)

    def test_in_range_bass_does_not_move_toward_prior(self):
        self.assertEqual(self.recommend(40).adjustments['bass'].recommended, 4)

    def test_clipping_blocks_tone_boost(self):
        result = generate_recommendation(request(
            measurements=dict(loudness=40, bass=0, treble=0, sharpness=40, flatness=40),
            safety=SafetySignals(clipping=True)), self.profile)
        for knob in ('bass', 'treble'):
            self.assertEqual(result.adjustments[knob].delta, 0)
            self.assertEqual(result.adjustments[knob].reason_code, 'tone_increase_blocked_by_distortion')

    def test_verification_cap_and_hardware_boundaries(self):
        self.assertEqual(self.recommend(80, verification=True).adjustments['bass'].recommended, 3)
        self.assertEqual(self.recommend(0, current=10).adjustments['bass'].recommended, 10)
        self.assertEqual(self.recommend(80, current=-10).adjustments['bass'].recommended, -10)

    def test_artifact_has_fifteen_recordings_per_genre_and_negative_rnb_prior(self):
        artifact = load_genre_profiles()
        self.assertEqual(set(artifact.genres), {'pop', 'rock', 'r&b'})
        self.assertTrue(all(p.sample_count == 15 for p in artifact.genres.values()))
        self.assertLess(artifact.profile_for('rnb').knob_preferences['bass'].preferred, 0)

    def test_score_and_recommendation_agree_about_excess_bass(self):
        artifact = load_genre_profiles()
        p = artifact.profile_for('pop')
        values = {name: metric.preferred for name, metric in p.metrics.items()}
        good = score_genre_values(values, 'pop')
        values['bass'] = p.metrics['bass'].upper + 2 * p.metrics['bass'].robust_scale
        bad = score_genre_values(values, 'pop')
        self.assertLess(bad['overall_score'], good['overall_score'])
        self.assertEqual(bad['features']['bass']['direction'], 'above')
        result = generate_recommendation(request(measurements=values), p)
        self.assertLess(result.adjustments['bass'].delta, 0)
        self.assertEqual(good['quality_profile_checksum'], bad['quality_profile_checksum'])

    def test_invalid_provenance_rejected_even_with_recomputed_checksum(self):
        import json
        from pathlib import Path
        data = json.loads((Path(__file__).resolve().parents[1] / 'audio_thresholds/genre_audio_profiles.json').read_text())
        data['sources']['recordings'].pop()
        data['artifact_checksum'] = canonical_artifact_checksum(data)
        with self.assertRaises(ValueError):
            parse_genre_profile_artifact(data)

    def test_missing_genre_leaves_existing_score_untouched(self):
        dump = {'empirical_quality': {'overall_score': 65}}
        apply_genre_evaluation(dump, None)
        self.assertEqual(dump['empirical_quality']['overall_score'], 65)

    def test_attenuation_volume_moves_one_detent_in_loudness_direction(self):
        for loudness, expected in [(0, 50), (40, 60), (80, 70)]:
            with self.subTest(loudness=loudness):
                result = generate_recommendation(request(
                    scale=AmplifierScale(-10, 10, .5),
                    current=KnobSettings(60, 0, 0, 0, 0, volume_attenuation=True),
                    measurements=dict(loudness=loudness, bass=40, treble=40, sharpness=40, flatness=40)), self.profile)
                self.assertEqual(result.adjustments['volume'].recommended, expected)
                self.assertTrue(result.to_dict()['recommended']['volume_attenuation'])

    def test_attenuation_boost_blocked_by_clipping_and_mute_not_unmuted(self):
        for current, safety in [(60, SafetySignals(clipping=True)), (110, SafetySignals())]:
            result = generate_recommendation(request(
                current=KnobSettings(current, 0, 0, 0, 0, volume_attenuation=True),
                measurements=dict(loudness=0, bass=40, treble=40, sharpness=40, flatness=40),
                safety=safety), self.profile)
            self.assertEqual(result.adjustments['volume'].recommended, current)

    def test_optional_controls_reset_deterministically_to_zero(self):
        r = request(current=KnobSettings(5, 5, 5, 7, 0))
        first = generate_recommendation(r, self.profile)
        self.assertEqual(first, generate_recommendation(r, self.profile))
        self.assertEqual(first.adjustments['sharpness'].recommended, 0)
        self.assertEqual(first.adjustments['sharpness'].delta, -7)
        self.assertEqual(first.adjustments['flatness'].reason_code, 'optional_control_unchanged')

    def test_volume_scale_round_trips_through_guest_verification_and_profiles(self):
        import os
        os.environ.setdefault('JWT_SECRET', 'test-only-secret-that-is-at-least-32-characters')
        from karaok.audio_pipeline.recommendations import issue_guest_verification_token, parse_guest_verification_token
        from karaok.core.recommendation_contracts import _knob_settings, _same_positions
        from karaok.results.profiles import _positions
        artifact = load_genre_profiles()
        p = artifact.profile_for('pop')
        scale = AmplifierScale(-10, 10, .5)
        current = KnobSettings(60, 0, 0, 0, 0, volume_attenuation=True)
        stored = _positions(current.to_dict(), minimum=-10, maximum=10)
        self.assertTrue(_same_positions(current, _knob_settings(stored, scale, 'stored'), scale))
        r = replace(request(scale=scale, current=current,
            measurements={name: metric.preferred for name, metric in p.metrics.items()}),
            profile_version=artifact.profile_version, profile_checksum=artifact.artifact_checksum)
        result = generate_recommendation(r, p)
        token = issue_guest_verification_token(result, scale, before_score=80)
        context = parse_guest_verification_token(token)
        self.assertTrue(context.recommended_positions.volume_attenuation)
        self.assertEqual(context.recommended_positions.volume, 60)
        with self.assertRaises(ValueError):
            _knob_settings({**stored, 'volume': 65}, scale, 'invalid')
        with self.assertRaises(ValueError):
            _knob_settings({**stored, 'volume_attenuation': 'true'}, scale, 'invalid')

    def test_evaluation_summary_uses_genre_score_before_persistence(self):
        p = load_genre_profiles().profile_for('rnb')
        fields = dict(loudness='integrated_lufs', bass='energy_percentage',
                      treble='energy_percentage', sharpness='normalized_score', flatness='mean')
        dump = {'analysis': {key: {field: p.metrics[key].preferred} for key, field in fields.items()},
                'empirical_quality': {'overall_score': 12}}
        apply_genre_evaluation(dump, 'rnb')
        summary = summarize_audio_analysis(dump)
        self.assertAlmostEqual(summary['score'], 100)
        self.assertEqual(summary['empirical_quality']['reference_recording_count'], 15)
        self.assertEqual(summary['empirical_quality']['genre'], 'r&b')


if __name__ == '__main__':
    unittest.main()
