import unittest
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

    def test_steady_10db_within_tolerance(self):
        self.assert_cell("steady", 10)

    def test_transient_20db_within_tolerance(self):
        self.assert_cell("transient", 20)

    def test_transient_10db_within_tolerance(self):
        self.assert_cell("transient", 10)

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
