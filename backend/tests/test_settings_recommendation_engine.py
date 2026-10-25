import json
import math
import unittest
from pathlib import Path
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
    def test_volume_endpoint_recommendations_remain_on_step_and_reparse(self):
        for minimum, maximum, step, current, loudness, expected in (
            (0, 1, 0.3, 0.9, 0, 0.9),
            (-1, 0, 0.3, -0.1, 0, -0.1),
            (0.1, 1.1, 0.3, 1.0, 0, 1.0),
            (0, 1, 0.12, 0.84, 0, 0.96),
            (0, 1, 0.1, 0.9, 0, 1.0),
            (0, 1, 0.1, 0.1, 80, 0.0),
        ):
            with self.subTest(minimum=minimum, maximum=maximum, step=step, current=current):
                result = generate_recommendation(request(
                    current=KnobSettings(current, 50, 50, 50, 50, volume_scale={
                        "minimum": minimum, "maximum": maximum, "step": step, "unit": ""}),
                    measurements=dict(loudness=loudness, bass=40, treble=40, sharpness=40, flatness=40)),
                    profile())
                adjustment = result.adjustments["volume"]
                self.assertAlmostEqual(adjustment.recommended, expected)
                self.assertLessEqual(abs(adjustment.delta_normalized), 15)
                self.assertGreaterEqual(adjustment.recommended, minimum)
                self.assertLessEqual(adjustment.recommended, maximum)
                # The public output must be usable as the next recording snapshot.
                snapshot = KnobSettings(**result.to_dict()["recommended"])
                self.assertEqual(snapshot.volume, adjustment.recommended)

    def test_independent_db_volume_uses_own_range_step_and_delta_cap(self):
        genre_profile = load_genre_profiles().genres["rock"]
        for verification, expected in ((False, -52), (True, -56)):
            for safety in (SafetySignals(), SafetySignals(clipping=True),
                           SafetySignals(excessive_distortion=True)):
                measurements = {k: t.preferred for k, t in genre_profile.metrics.items()}
                measurements["loudness"] = genre_profile.metrics["loudness"].lower - 100
                result = generate_recommendation(request(
                    scale=AmplifierScale(-10, 10, 0.5),
                    current=KnobSettings(-60, 0, 0, 0, 0, volume_scale={
                        "minimum": -80, "maximum": 0, "step": 1, "unit": "dB"}),
                    measurements=measurements, verification=verification, safety=safety), genre_profile)
                adjustment = result.adjustments["volume"]
                blocked = safety.clipping or safety.excessive_distortion
                self.assertEqual(adjustment.recommended, -60 if blocked else expected)
                self.assertEqual(adjustment.delta_normalized, 0 if blocked else (5 if verification else 10))
                self.assertEqual(result.adjustments["bass"].delta, 0)
                self.assertEqual(result.to_dict()["recommended"]["volume_scale"]["unit"], "dB")

    def technician_recordings(self):
        path = Path(__file__).resolve().parents[1] / "audio_thresholds" / "genre_audio_profiles.json"
        return json.loads(path.read_text(encoding="utf-8"))["sources"]["recordings"]

    def test_independent_volume_cuts_round_on_own_step_and_stop_at_boundary(self):
        genre_profile = load_genre_profiles().genres["pop"]
        measurements = {k: t.preferred for k, t in genre_profile.metrics.items()}
        measurements["loudness"] = genre_profile.metrics["loudness"].upper + 100
        for current, expected, delta in ((-60, -68, -10), (-79, -80, -1.25)):
            result = generate_recommendation(request(
                scale=AmplifierScale(-10, 10, 0.5),
                current=KnobSettings(current, 0, 0, 0, 0, volume_scale={
                    "minimum": -80, "maximum": 0, "step": 1, "unit": "dB"}),
                measurements=measurements), genre_profile)
            self.assertEqual(result.adjustments["volume"].recommended, expected)
            self.assertEqual(result.adjustments["volume"].delta_normalized, delta)

    def test_recorded_samples_produce_stronger_genre_specific_tone_corrections(self):
        artifact = load_genre_profiles()
        recordings = {row["recording_id"]: row for row in self.technician_recordings()}
        expected = {
            "pop-01": {"pop": (3, 2), "r&b": (0, 1), "rock": (3, 0)},
            "pop-10": {"pop": (-2, 0), "r&b": (-3, 0), "rock": (0, 0)},
            "pop-11": {"pop": (0, -2), "r&b": (-2, -3), "rock": (3, -3)},
        }
        for recording_id, genres in expected.items():
            for genre, deltas in genres.items():
                with self.subTest(recording=recording_id, genre=genre):
                    result = generate_recommendation(
                        request(scale=AmplifierScale(-10, 10, 1),
                                current=KnobSettings(0, 0, 0, 0, 0),
                                measurements=recordings[recording_id]["measurements"]),
                        artifact.genres[genre],
                    )
                    self.assertEqual(tuple(result.adjustments[k].delta for k in ("bass", "treble")), deltas)

    def test_recorded_corpus_preserves_tone_dead_zone_direction_and_caps(self):
        artifact = load_genre_profiles()
        for row in self.technician_recordings():
            for genre_profile in artifact.genres.values():
                for scale in (AmplifierScale(-10, 10, 1), AmplifierScale(0, 100, 0.5),
                              AmplifierScale(0, 10, 2)):
                    for verification in (False, True):
                        current = scale.minimum + (scale.maximum - scale.minimum) / 2
                        for position in (scale.minimum, current, scale.maximum):
                            with self.subTest(recording=row["recording_id"], genre=genre_profile.key,
                                              scale=scale, verification=verification, position=position):
                                result = generate_recommendation(
                                    request(scale=scale, current=KnobSettings(position, position, position, 0, 0),
                                            measurements=row["measurements"], verification=verification),
                                    genre_profile,
                                )
                                for knob in ("bass", "treble"):
                                    adjustment = result.adjustments[knob]
                                    target = genre_profile.metrics[knob]
                                    measured = row["measurements"][knob]
                                    self.assertLessEqual(abs(adjustment.delta_normalized), 7.5 if verification else 15)
                                    self.assertLessEqual(scale.minimum, adjustment.recommended)
                                    self.assertGreaterEqual(scale.maximum, adjustment.recommended)
                                    if target.lower <= measured <= target.upper:
                                        self.assertEqual(adjustment.delta, 0)
                                    else:
                                        self.assertGreaterEqual(adjustment.delta * (target.preferred - measured), 0)

    def test_stronger_tones_still_block_unsafe_boosts_and_allow_cuts(self):
        genre_profile = load_genre_profiles().genres["rock"]
        for safety in (SafetySignals(clipping=True), SafetySignals(excessive_distortion=True)):
            for above in (False, True):
                measurements = {k: t.preferred for k, t in genre_profile.metrics.items()}
                for knob in ("bass", "treble"):
                    target = genre_profile.metrics[knob]
                    measurements[knob] = target.upper + target.robust_scale if above else target.lower - target.robust_scale
                result = generate_recommendation(
                    request(scale=AmplifierScale(-10, 10, 1), current=KnobSettings(0, 0, 0, 0, 0),
                            measurements=measurements, safety=safety), genre_profile)
                for knob in ("bass", "treble"):
                    self.assertEqual(result.adjustments[knob].delta, -3 if above else 0)
                    if not above:
                        self.assertEqual(result.adjustments[knob].reason_code, "tone_increase_blocked_by_distortion")

    def test_technician_tone_caps_expand_without_expanding_volume(self):
        genre_profile = load_genre_profiles().genres["rock"]
        measurements = {k: t.lower - 10 * t.robust_scale for k, t in genre_profile.metrics.items()}
        for verification, tone_delta, volume_delta in ((False, 3, 2), (True, 1.5, 1)):
            result = generate_recommendation(
                request(scale=AmplifierScale(-10, 10, 0.5), current=KnobSettings(0, 0, 0, 0, 0),
                        measurements=measurements, verification=verification), genre_profile)
            self.assertEqual(result.adjustments["volume"].delta, volume_delta)
            for knob in ("bass", "treble"):
                self.assertEqual(result.adjustments[knob].delta, tone_delta)

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
                    current=KnobSettings(5.0, 5.0, 5.0, 0.0, 0.0),
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
