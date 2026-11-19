import unittest
from copy import deepcopy
from functools import lru_cache
from pathlib import Path
from runpy import run_path

import numpy as np

from audio_engine.noise_guard_eval import analyze_samples, compare, run_case
from tests.noise_fixtures import babble, chicken_bursts, engine_noise, music_like


class NoiseGuardAcceptanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sr = 44100
        cls.song = music_like(cls.sr, 20, 7)
        cls.clean = analyze_samples(cls.song, cls.sr)
        cls.noise = {
            category: fixture(cls.sr, 23, 1)
            for category, fixture in (
                ("steady", engine_noise), ("transient", chicken_bursts), ("babble", babble)
            )
        }

    @classmethod
    @lru_cache(maxsize=None)
    def case(cls, category, mnr, guard=True):
        return run_case(cls.song, cls.noise[category], cls.sr, mnr, guard)

    def assert_cell(self, category, mnr):
        result = compare(self.clean, self.case(category, mnr))
        self.assertTrue(result["passed"], result)

    def test_steady_20db_within_tolerance(self):
        self.assert_cell("steady", 20)

    def assert_flagged(self, category):
        report = self.case(category, 10)["noise_guard"]
        self.assertIn(report["confidence"], ("low", "medium"))
        self.assertTrue(report["warnings"])

    def test_steady_10db_is_flagged(self):
        self.assert_flagged("steady")

    def test_transient_20db_within_tolerance(self):
        self.assert_cell("transient", 20)

    def test_transient_10db_is_flagged(self):
        self.assert_flagged("transient")

    def test_babble_20db_within_tolerance(self):
        self.assert_cell("babble", 20)

    def test_guard_improves_on_baseline_steady_10db(self):
        baseline = compare(self.clean, self.case("steady", 10, False))
        self.assertTrue(any(not metric["ok"] for metric in baseline["metrics"].values()), baseline)
        self.assert_cell("steady", 10)

    def test_low_mnr_is_flagged(self):
        for category in ("steady", "babble"):
            with self.subTest(category=category):
                report = self.case(category, 5)["noise_guard"]
                self.assertEqual(report["confidence"], "low", report)

    def test_compare_reports_unreliable_flatness_without_failing_tolerance(self):
        clean = deepcopy(self.clean)
        clean["flatness"]["mean"] = 0.000001
        noisy = deepcopy(clean)
        noisy["flatness"].update(mean=0.000015, reliable=True)
        ordinary = compare(clean, noisy)
        self.assertFalse(ordinary["passed"], ordinary)
        noisy["flatness"]["reliable"] = False
        unreliable = compare(clean, noisy)
        self.assertTrue(unreliable["passed"], unreliable)
        self.assertTrue(unreliable["metrics"]["flatness"]["skipped"])
        self.assertEqual(unreliable["metrics"]["flatness"]["delta"], ordinary["metrics"]["flatness"]["delta"])
        self.assertEqual(unreliable["metrics"]["score"], ordinary["metrics"]["score"])


class NoiseGuardMixTests(unittest.TestCase):
    def test_rejects_mixture_above_full_scale(self):
        sr = 8000
        clean = np.full(10 * sr, 0.95)
        noise = np.ones(13 * sr)
        with self.assertRaisesRegex(ValueError, "the analyzer would rescale it"):
            run_case(clean, noise, sr, 5, True)


class NoiseGuardCliTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cli_path = Path(__file__).resolve().parents[2] / "tools/noise_guard_eval.py"
        cls.cli = run_path(str(cli_path))

    def test_specific_category_overrides_default_substring(self):
        category = self.cli["category_for"]("jeep downtown", {"jeep downtown": "transient"})
        self.assertEqual(category, "transient")

    def test_grid_orders_observed_categories(self):
        ordered = self.cli["grid_categories"](["transient", "babble", "steady", "custom"])
        self.assertEqual(ordered, ["steady", "transient", "babble", "custom"])

    def test_quiet_room_floor_matches_in_preroll_and_song(self):
        sr = 8000
        clean = np.full(2 * sr, 0.125, dtype=np.float32)
        recording = self.cli["quiet_recording"](clean, sr)
        preroll = recording[:3 * sr]
        added_noise = recording[3 * sr:] - clean
        for segment in (preroll, added_noise):
            self.assertAlmostEqual(10 * np.log10(np.mean(segment ** 2)), -70, places=3)

    def test_flagging_requires_both_confidence_and_warning(self):
        flagged = self.cli["is_flagged"]
        self.assertTrue(flagged(dict(confidence="medium", warnings=["Noise warning"])))
        self.assertFalse(flagged(dict(confidence="medium", warnings=[])))
        self.assertFalse(flagged(dict(confidence="high", warnings=["Noise warning"])))

    def test_street_mix_aligns_sources_and_gives_each_equal_rms(self):
        recordings = []
        sources = (
            ("jeep.mp3", 80, 2000, 1, 0.01),
            ("chicken.mp3", 120, 4000, 2, 0.1),
            ("motorcycle.mp3", 160, 4000, 2, 0.3),
            ("Human talk.mp3", 200, 4000, 2, 0.6),
        )
        for name, frequency, rate, seconds, amplitude in sources:
            times = np.arange(rate * seconds) / rate
            audio = amplitude * np.sin(2 * np.pi * frequency * times)
            recordings.append((Path(name), "custom", audio, rate))

        path, category, audio, rate = self.cli["build_street_mix"](recordings)

        self.assertEqual((path.name, category, rate), ("street_mix", "street_mix", 4000))
        self.assertEqual(len(audio), 4000)
        magnitudes = np.abs(np.fft.rfft(audio))
        contributions = [magnitudes[frequency] for _, frequency, *_ in sources]
        np.testing.assert_allclose(contributions, [contributions[0]] * 4, rtol=0.002)
        self.assertNotIn(category, self.cli["MUST_PASS_MNR"])

    def test_street_mix_requires_all_four_named_recordings(self):
        recordings = [(Path("jeep.mp3"), "steady", np.ones(4), 4)]

        self.assertIsNone(self.cli["build_street_mix"](recordings))
