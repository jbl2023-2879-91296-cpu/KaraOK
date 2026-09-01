import json
import unittest
from pathlib import Path

from audio_thresholds.genre_profiles import (
    load_genre_profiles,
    normalize_genre,
    parse_genre_profile_artifact,
)


FIXTURES = Path(__file__).resolve().parent / "fixtures"


def valid_payload():
    return json.loads(
        (FIXTURES / "genre_audio_profiles.valid.json").read_text(encoding="utf-8")
    )


class GenreProfileTests(unittest.TestCase):
    def test_normalizes_supported_labels(self):
        self.assertEqual(normalize_genre("HipHop"), "hip-hop")
        self.assertEqual(normalize_genre("Classic"), "classical")
        self.assertEqual(normalize_genre("Soul-RnB"), "r&b")

    def test_loads_complete_five_metric_profile(self):
        artifact = load_genre_profiles(FIXTURES / "genre_audio_profiles.valid.json")
        rock = artifact.profile_for("Rock")
        self.assertEqual(
            set(rock.metrics), {"loudness", "bass", "treble", "sharpness", "flatness"}
        )
        self.assertLess(rock.metrics["bass"].lower, rock.metrics["bass"].preferred)

    def test_rejects_degenerate_metric_range(self):
        payload = valid_payload()
        payload["genres"]["rock"]["metrics"]["bass"]["upper"] = payload["genres"]["rock"]["metrics"]["bass"]["preferred"]
        with self.assertRaisesRegex(ValueError, "lower < preferred < upper"):
            parse_genre_profile_artifact(payload)


if __name__ == "__main__":
    unittest.main()
