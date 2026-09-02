import json
import math
import unittest
from types import MappingProxyType

from audio_thresholds.genre_profiles import (
    GenreProfile,
    MetricTarget,
    load_genre_profiles,
)
from settings_recommendations import (
    ALGORITHM_VERSION,
    AmplifierScale,
    KnobSettings,
    RecommendationRequest,
    SafetySignals,
    generate_recommendation,
)


KNOBS = ("volume", "bass", "treble", "sharpness", "flatness")
METRICS = ("loudness", "bass", "treble", "sharpness", "flatness")


def profile(
    *,
    sample_count=20,
    missing_metric=None,
    corpus_status="confirmed_instrumental",
):
    metrics = {
        metric: MetricTarget(
            lower=30.0,
            preferred=40.0,
            upper=50.0,
            robust_scale=10.0,
            unit="test-unit",
        )
        for metric in METRICS
        if metric != missing_metric
    }
    return GenreProfile(
        key="rock",
        sample_count=sample_count,
        corpus_status=corpus_status,
        metrics=MappingProxyType(metrics),
    )


def request(
    *,
    scale=None,
    current=None,
    measurements=None,
    safety=None,
    verification=False,
    profile_checksum="a" * 64,
    hardware_response_characterized=True,
):
    return RecommendationRequest(
        scale=scale or AmplifierScale(0.0, 100.0, 0.5),
        current=current or KnobSettings(50.0, 50.0, 50.0, 50.0, 50.0),
        measurements=measurements
        or {
            "loudness": 40.0,
            "bass": 40.0,
            "treble": 40.0,
            "sharpness": 40.0,
            "flatness": 40.0,
        },
        safety=safety or SafetySignals(),
        verification=verification,
        profile_version="test-profile-1",
        profile_checksum=profile_checksum,
        hardware_response_characterized=hardware_response_characterized,
    )


class SettingsRecommendationEngineTests(unittest.TestCase):
    def test_scale_validates_values_and_rounds_to_supported_increment(self):
        scale = AmplifierScale(0.0, 10.0, 0.5)
        self.assertEqual(scale.normalize(5.5), 55.0)
        self.assertEqual(scale.denormalize(53.0), 5.5)

        for invalid in (
            (-1.0, -1.0, 0.5),
            (0.0, 10.0, 0.0),
            (0.0, math.inf, 0.5),
        ):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                AmplifierScale(*invalid)

        with self.assertRaises(ValueError):
            scale.normalize(10.5)

    def test_rejects_non_finite_or_out_of_range_current_positions(self):
        scale = AmplifierScale(0.0, 10.0, 0.5)
        for values in (
            (math.nan, 5.0, 5.0, 5.0, 5.0),
            (5.0, 11.0, 5.0, 5.0, 5.0),
        ):
            with self.subTest(values=values), self.assertRaises(ValueError):
                request(scale=scale, current=KnobSettings(*values))

    def test_keeps_every_setting_inside_its_genre_dead_zone(self):
        result = generate_recommendation(request(), profile())

        self.assertEqual(result.status, "generated")
        for knob in KNOBS:
            with self.subTest(knob=knob):
                adjustment = result.adjustments[knob]
                self.assertEqual(adjustment.recommended, 50.0)
                self.assertEqual(adjustment.delta_normalized, 0.0)
                self.assertEqual(adjustment.reason_code, "within_genre_range")

    def test_uses_explicit_knob_to_measurement_mapping_in_both_directions(self):
        mapping = dict(zip(KNOBS, METRICS, strict=True))
        for knob, metric in mapping.items():
            with self.subTest(knob=knob, direction="increase"):
                measurements = {name: 40.0 for name in METRICS}
                measurements[metric] = 0.0
                result = generate_recommendation(
                    request(measurements=measurements), profile()
                )
                self.assertEqual(result.adjustments[knob].recommended, 65.0)
                self.assertEqual(
                    result.adjustments[knob].reason_code, "below_genre_range"
                )

            with self.subTest(knob=knob, direction="decrease"):
                measurements = {name: 40.0 for name in METRICS}
                measurements[metric] = 80.0
                result = generate_recommendation(
                    request(measurements=measurements), profile()
                )
                self.assertEqual(result.adjustments[knob].recommended, 35.0)
                self.assertEqual(
                    result.adjustments[knob].reason_code, "above_genre_range"
                )

    def test_caps_initial_and_verification_adjustments(self):
        measurements = {name: 0.0 for name in METRICS}
        initial = generate_recommendation(
            request(measurements=measurements), profile()
        )
        verification = generate_recommendation(
            request(measurements=measurements, verification=True), profile()
        )

        self.assertEqual(initial.adjustments["bass"].delta_normalized, 15.0)
        self.assertEqual(verification.adjustments["bass"].delta_normalized, 7.5)

    def test_physical_increment_rounding_never_exceeds_the_verification_cap(self):
        scale = AmplifierScale(0.0, 10.0, 1.0)
        current = KnobSettings(5.0, 5.0, 5.0, 5.0, 5.0)
        measurements = {name: 0.0 for name in METRICS}

        result = generate_recommendation(
            request(
                scale=scale,
                current=current,
                measurements=measurements,
                verification=True,
            ),
            profile(),
        )

        for adjustment in result.adjustments.values():
            self.assertLessEqual(abs(adjustment.delta_normalized), 7.5)

    def test_dead_zone_does_not_snap_an_acceptable_current_position(self):
        scale = AmplifierScale(0.0, 10.0, 0.5)
        current = KnobSettings(5.3, 5.3, 5.3, 5.3, 5.3)

        result = generate_recommendation(
            request(scale=scale, current=current),
            profile(),
        )

        for adjustment in result.adjustments.values():
            self.assertEqual(adjustment.recommended, 5.3)
            self.assertEqual(adjustment.delta, 0.0)
            self.assertEqual(adjustment.delta_normalized, 0.0)

    def test_clamps_targets_to_the_physical_scale(self):
        below = {name: 0.0 for name in METRICS}
        above = {name: 80.0 for name in METRICS}
        high = KnobSettings(95.0, 95.0, 95.0, 95.0, 95.0)
        low = KnobSettings(5.0, 5.0, 5.0, 5.0, 5.0)

        increased = generate_recommendation(
            request(current=high, measurements=below), profile()
        )
        decreased = generate_recommendation(
            request(current=low, measurements=above), profile()
        )

        self.assertEqual(increased.adjustments["bass"].recommended, 100.0)
        self.assertEqual(increased.adjustments["bass"].delta_normalized, 5.0)
        self.assertEqual(decreased.adjustments["bass"].recommended, 0.0)
        self.assertEqual(decreased.adjustments["bass"].delta_normalized, -5.0)

    def test_converts_normalized_delta_to_physical_scale_and_increment(self):
        scale = AmplifierScale(0.0, 10.0, 0.5)
        current = KnobSettings(5.0, 4.0, 6.0, 5.0, 5.0)
        measurements = {name: 40.0 for name in METRICS}
        measurements["bass"] = 0.0

        result = generate_recommendation(
            request(scale=scale, current=current, measurements=measurements),
            profile(),
        )

        bass = result.adjustments["bass"]
        self.assertEqual(bass.current, 4.0)
        self.assertEqual(bass.recommended, 5.5)
        self.assertEqual(bass.delta, 1.5)
        self.assertEqual(bass.delta_normalized, 15.0)

    def test_clipping_or_distortion_blocks_only_a_volume_increase(self):
        measurements = {name: 40.0 for name in METRICS}
        measurements["loudness"] = 0.0

        for safety, reason in (
            (SafetySignals(clipping=True), "volume_increase_blocked_by_clipping"),
            (
                SafetySignals(excessive_distortion=True),
                "volume_increase_blocked_by_distortion",
            ),
        ):
            with self.subTest(reason=reason):
                result = generate_recommendation(
                    request(measurements=measurements, safety=safety), profile()
                )
                volume = result.adjustments["volume"]
                self.assertEqual(volume.recommended, 50.0)
                self.assertEqual(volume.delta_normalized, 0.0)
                self.assertEqual(volume.reason_code, reason)

    def test_clipping_still_allows_a_safe_volume_decrease(self):
        measurements = {name: 40.0 for name in METRICS}
        measurements["loudness"] = 80.0
        result = generate_recommendation(
            request(measurements=measurements, safety=SafetySignals(clipping=True)),
            profile(),
        )

        self.assertEqual(result.adjustments["volume"].recommended, 35.0)
        self.assertEqual(
            result.adjustments["volume"].reason_code, "above_genre_range"
        )

    def test_missing_or_non_finite_measurement_makes_all_settings_unavailable(self):
        cases = []
        missing = {name: 40.0 for name in METRICS if name != "flatness"}
        cases.append((missing, "missing_required_measurement"))
        non_finite = {name: 40.0 for name in METRICS}
        non_finite["bass"] = math.nan
        cases.append((non_finite, "non_finite_measurement"))

        for measurements, reason in cases:
            with self.subTest(reason=reason):
                result = generate_recommendation(
                    request(measurements=measurements), profile()
                )
                self.assertEqual(result.status, "unavailable")
                self.assertEqual(result.overall_confidence, "unavailable")
                self.assertEqual(set(result.adjustments), set(KNOBS))
                for adjustment in result.adjustments.values():
                    self.assertIsNone(adjustment.recommended)
                    self.assertEqual(adjustment.reason_code, reason)

    def test_invalid_recording_signals_make_the_whole_result_unavailable(self):
        for safety, reason in (
            (SafetySignals(silent=True), "silent_recording"),
            (SafetySignals(corrupt=True), "corrupt_recording"),
            (SafetySignals(too_short=True), "recording_too_short"),
        ):
            with self.subTest(reason=reason):
                result = generate_recommendation(
                    request(safety=safety), profile()
                )
                self.assertEqual(result.status, "unavailable")
                self.assertTrue(
                    all(
                        adjustment.reason_code == reason
                        for adjustment in result.adjustments.values()
                    )
                )

    def test_missing_profile_metric_or_low_confidence_measurement_is_unavailable(self):
        missing = generate_recommendation(request(), profile(missing_metric="treble"))
        low_confidence = generate_recommendation(
            request(safety=SafetySignals(low_confidence_metrics={"bass"})),
            profile(),
        )

        self.assertEqual(missing.status, "unavailable")
        self.assertEqual(
            missing.adjustments["treble"].reason_code,
            "missing_required_profile_metric",
        )
        self.assertEqual(low_confidence.status, "unavailable")
        self.assertEqual(
            low_confidence.adjustments["bass"].reason_code,
            "low_confidence_measurement",
        )

    def test_malformed_profile_metric_makes_the_whole_result_unavailable(self):
        metrics = dict(profile().metrics)
        metrics["bass"] = MetricTarget(30.0, 40.0, 50.0, 0.0, "test-unit")
        malformed = GenreProfile(
            "rock",
            20,
            "confirmed_instrumental",
            MappingProxyType(metrics),
        )

        result = generate_recommendation(request(), malformed)

        self.assertEqual(result.status, "unavailable")
        self.assertTrue(
            all(
                adjustment.reason_code == "invalid_genre_profile"
                for adjustment in result.adjustments.values()
            )
        )

    def test_confidence_accounts_for_cross_coupling_profile_size_and_warnings(self):
        clean = generate_recommendation(request(), profile(sample_count=20))
        noisy = generate_recommendation(
            request(safety=SafetySignals(excessive_noise=True)),
            profile(sample_count=5),
        )

        self.assertEqual(clean.adjustments["volume"].confidence, "high")
        self.assertEqual(clean.adjustments["bass"].confidence, "medium")
        self.assertEqual(clean.overall_confidence, "medium")
        self.assertEqual(noisy.adjustments["volume"].confidence, "low")
        self.assertEqual(noisy.adjustments["bass"].confidence, "low")
        self.assertEqual(noisy.overall_confidence, "low")

    def test_unverified_or_small_genre_corpus_never_claims_high_confidence(self):
        unverified = profile(sample_count=5, corpus_status="unverified")

        result = generate_recommendation(
            request(
                profile_checksum="a" * 64,
                hardware_response_characterized=False,
            ),
            unverified,
        )

        self.assertEqual(result.adjustments["volume"].confidence, "low")
        self.assertEqual(result.overall_confidence, "low")
        self.assertEqual(result.profile_checksum, "a" * 64)

    def test_request_and_result_mappings_are_immutable(self):
        recommendation_request = request()
        result = generate_recommendation(recommendation_request, profile())

        with self.assertRaises(TypeError):
            recommendation_request.measurements["bass"] = 0.0
        with self.assertRaises(TypeError):
            result.adjustments["bass"] = result.adjustments["bass"]

    def test_serialization_is_structured_complete_and_deterministic(self):
        for invalid_checksum in ("a" * 63, "A" * 64, "g" * 64):
            with self.subTest(invalid_checksum=invalid_checksum):
                with self.assertRaisesRegex(ValueError, "profile_checksum"):
                    request(profile_checksum=invalid_checksum)

        recommendation_request = request()
        first = generate_recommendation(recommendation_request, profile())
        second = generate_recommendation(recommendation_request, profile())

        self.assertEqual(first, second)
        payload = first.to_dict()
        self.assertEqual(payload["algorithm_version"], ALGORITHM_VERSION)
        self.assertEqual(payload["profile_version"], "test-profile-1")
        self.assertEqual(payload["profile_checksum"], "a" * 64)
        self.assertEqual(payload["genre"], "rock")
        self.assertEqual(set(payload["current"]), set(KNOBS))
        self.assertEqual(set(payload["recommended"]), set(KNOBS))
        self.assertEqual(set(payload["adjustments"]), set(KNOBS))
        self.assertEqual(
            payload["adjustments"]["bass"]["reason_code"],
            "within_genre_range",
        )
        json.dumps(payload, allow_nan=False)

    def test_consumes_every_committed_genre_profile_without_adaptation(self):
        artifact = load_genre_profiles()
        for genre_profile in artifact.genres.values():
            with self.subTest(genre=genre_profile.key):
                measurements = {
                    metric: target.preferred
                    for metric, target in genre_profile.metrics.items()
                }
                recommendation_request = RecommendationRequest(
                    scale=AmplifierScale(0.0, 10.0, 0.5),
                    current=KnobSettings(5.0, 5.0, 5.0, 5.0, 5.0),
                    measurements=measurements,
                    profile_version=artifact.profile_version,
                    profile_checksum=artifact.artifact_checksum,
                    hardware_response_characterized=True,
                )

                result = generate_recommendation(
                    recommendation_request,
                    genre_profile,
                )

                self.assertEqual(result.status, "generated")
                self.assertTrue(
                    all(
                        adjustment.delta_normalized == 0.0
                        for adjustment in result.adjustments.values()
                    )
                )


if __name__ == "__main__":
    unittest.main()
