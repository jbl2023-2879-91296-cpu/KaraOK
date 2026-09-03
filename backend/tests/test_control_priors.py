import json
import unittest
from pathlib import Path

from audio_thresholds.artifact_integrity import canonical_artifact_checksum
from audio_thresholds.control_priors import (
    clear_control_prior_cache,
    load_control_priors,
    parse_control_priors,
)


CONTROL_PRIORS_PATH = (
    Path(__file__).resolve().parents[1]
    / "audio_thresholds"
    / "amplifier_control_priors.json"
)


def valid_payload():
    return json.loads(CONTROL_PRIORS_PATH.read_text(encoding="utf-8"))


def with_valid_checksum(payload):
    payload["artifact_checksum"] = canonical_artifact_checksum(payload)
    return payload


class ControlPriorTests(unittest.TestCase):
    def tearDown(self):
        clear_control_prior_cache()

    def test_loads_the_researched_normalized_positions(self):
        artifact = load_control_priors()

        self.assertEqual(artifact.prior_version, "2026.09.1")
        self.assertEqual(
            artifact.positions,
            {
                "volume": 40.0,
                "bass": 50.0,
                "treble": 50.0,
                "sharpness": 50.0,
                "flatness": 50.0,
            },
        )
        self.assertTrue(artifact.requires_physical_confirmation)

    def test_rejects_unknown_or_missing_artifact_keys(self):
        payload = valid_payload()
        payload["unexpected"] = "nope"
        with self.assertRaisesRegex(ValueError, "fields"):
            parse_control_priors(with_valid_checksum(payload))

        payload = valid_payload()
        del payload["sources"]
        with self.assertRaisesRegex(ValueError, "fields"):
            parse_control_priors(with_valid_checksum(payload))

    def test_rejects_non_finite_or_out_of_range_positions(self):
        for value in (float("nan"), float("inf"), float("-inf")):
            with self.subTest(value=value):
                payload = valid_payload()
                payload["positions"]["volume"] = value
                with self.assertRaises(ValueError):
                    parse_control_priors(payload)

        for value in ("NaN", "Infinity", -0.1, 100.1, True):
            with self.subTest(value=value):
                payload = valid_payload()
                payload["positions"]["volume"] = value
                with self.assertRaisesRegex(ValueError, "positions.volume|positions"):
                    parse_control_priors(with_valid_checksum(payload))

    def test_rejects_checksum_tampering(self):
        payload = valid_payload()
        payload["positions"]["volume"] = 41.0
        with self.assertRaisesRegex(ValueError, "checksum"):
            parse_control_priors(payload)

    def test_rejects_missing_or_invalid_research_citations(self):
        payload = valid_payload()
        payload["sources"] = []
        with self.assertRaisesRegex(ValueError, "sources"):
            parse_control_priors(with_valid_checksum(payload))

        payload = valid_payload()
        del payload["sources"][0]["url"]
        with self.assertRaisesRegex(ValueError, "source"):
            parse_control_priors(with_valid_checksum(payload))

    def test_repeat_loads_use_the_cached_immutable_artifact(self):
        first = load_control_priors()
        second = load_control_priors()

        self.assertIs(first, second)
        with self.assertRaises(TypeError):
            first.positions["volume"] = 10.0

if __name__ == "__main__":
    unittest.main()
