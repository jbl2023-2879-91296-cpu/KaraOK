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


def with_valid_checksum(payload):
    payload.pop("artifact_checksum", None)
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    import hashlib

    payload["artifact_checksum"] = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    return payload


class GenreProfileTests(unittest.TestCase):
    def _assert_schema_mutation_rejected(self, path, key, value=None, *, remove=False):
        payload = valid_payload()
        target = payload
        for part in path:
            target = target[part]
        if remove:
            del target[key]
        else:
            target[key] = value
        with self.assertRaises(ValueError):
            parse_genre_profile_artifact(with_valid_checksum(payload))

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
        payload["genres"]["rock"]["metrics"]["bass"]["upper"] = payload[
            "genres"
        ]["rock"]["metrics"]["bass"]["preferred"]
        with self.assertRaisesRegex(ValueError, "lower < preferred < upper"):
            parse_genre_profile_artifact(with_valid_checksum(payload))

    def test_rejects_bad_checksum_and_schema_version(self):
        payload = valid_payload()
        payload["artifact_checksum"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "checksum"):
            parse_genre_profile_artifact(payload)

        payload = valid_payload()
        payload["schema_version"] = 2
        with self.assertRaisesRegex(ValueError, "schema_version"):
            parse_genre_profile_artifact(payload)

    def test_rejects_duplicate_normalized_genres(self):
        payload = valid_payload()
        payload["genres"]["HipHop"] = payload["genres"]["rock"]
        payload["genres"]["hip-hop"] = payload["genres"]["rock"]
        with self.assertRaisesRegex(ValueError, "duplicate normalized genre"):
            parse_genre_profile_artifact(with_valid_checksum(payload))

    def test_requires_complete_auditable_source_metadata(self):
        for field in (
            "source",
            "release",
            "license",
            "citation_url",
            "selection_filters",
            "compatible_feature_notes",
            "calculation_method",
            "recordings",
        ):
            with self.subTest(field=field):
                payload = valid_payload()
                del payload["sources"][field]
                with self.assertRaises(ValueError):
                    parse_genre_profile_artifact(with_valid_checksum(payload))

    def test_requires_licensed_recording_cohort_matching_profile_sample_count(self):
        payload = valid_payload()
        payload["sources"]["recordings"] = payload["sources"]["recordings"][:-1]
        with self.assertRaisesRegex(ValueError, "licensed recording cohort"):
            parse_genre_profile_artifact(with_valid_checksum(payload))

        payload = valid_payload()
        payload["genres"]["rock"]["sample_count"] = 4
        with self.assertRaisesRegex(ValueError, "sample_count must be at least 5"):
            parse_genre_profile_artifact(with_valid_checksum(payload))

    def test_requires_recording_level_instrumental_status(self):
        payload = valid_payload()
        del payload["sources"]["recordings"][0]["instrumental_status"]

        with self.assertRaisesRegex(ValueError, "instrumental_status"):
            parse_genre_profile_artifact(with_valid_checksum(payload))

    def test_profile_corpus_status_matches_recording_evidence(self):
        payload = valid_payload()
        payload["genres"]["rock"]["corpus_status"] = "confirmed_instrumental"
        payload["sources"]["recordings"][0]["instrumental_status"] = "unverified"

        with self.assertRaisesRegex(ValueError, "corpus_status"):
            parse_genre_profile_artifact(with_valid_checksum(payload))

    def test_rejects_missing_or_malformed_metrics(self):
        payload = valid_payload()
        del payload["genres"]["rock"]["metrics"]["bass"]
        with self.assertRaisesRegex(ValueError, "exactly the supported metrics"):
            parse_genre_profile_artifact(with_valid_checksum(payload))

        payload = valid_payload()
        payload["genres"]["rock"]["metrics"]["bass"] = []
        with self.assertRaisesRegex(ValueError, "must be an object"):
            parse_genre_profile_artifact(with_valid_checksum(payload))

    def test_rejects_unknown_and_missing_fields_at_authoritative_levels(self):
        levels = (
            ((), "unexpected", False),
            ((), "generated_at", True),
            (("genres", "rock"), "unexpected", False),
            (("genres", "rock"), "sample_count", True),
            (("genres", "rock", "metrics"), "unexpected", False),
            (("genres", "rock", "metrics"), "bass", True),
            (("genres", "rock", "metrics", "bass"), "unexpected", False),
            (("genres", "rock", "metrics", "bass"), "lower", True),
            (("sources",), "unexpected", False),
            (("sources",), "license", True),
            (("sources", "recordings", 0), "unexpected", False),
            (("sources", "recordings", 0), "recording_id", True),
        )
        for path, key, remove in levels:
            with self.subTest(path=".".join(map(str, path)), key=key, remove=remove):
                self._assert_schema_mutation_rejected(
                    path,
                    key,
                    "unexpected",
                    remove=remove,
                )

    def test_rejects_invalid_source_and_recording_evidence_anchors(self):
        mutations = (
            (("sources",), "release", " "),
            (("sources",), "license", " "),
            (("sources",), "citation_url", "not-a-url"),
            (("sources",), "selection_filters", {}),
            (("sources",), "compatible_feature_notes", " "),
            (("sources",), "calculation_method", " "),
            (("sources", "recordings", 0), "genre", "jazz"),
            (("sources", "recordings", 0), "instrumental_status", "confirmed"),
            (("genres", "rock"), "corpus_status", "confirmed"),
        )
        for path, key, value in mutations:
            with self.subTest(path=".".join(map(str, path)), key=key, value=value):
                self._assert_schema_mutation_rejected(path, key, value)

    def test_rejects_invalid_target_units_coerced_types_and_non_finite_values(self):
        mutations = (
            ((), "schema_version", 1.0),
            (("genres", "rock"), "sample_count", 5.0),
            (("genres", "rock", "metrics", "bass"), "lower", "20.0"),
            (("genres", "rock", "metrics", "bass"), "preferred", True),
            (("genres", "rock", "metrics", "bass"), "upper", "NaN"),
            (("genres", "rock", "metrics", "bass"), "robust_scale", "Infinity"),
            (("genres", "rock", "metrics", "bass"), "unit", "ratio"),
            (("genres", "rock", "metrics", "loudness"), "unit", "dBFS"),
        )
        for path, key, value in mutations:
            with self.subTest(path=".".join(map(str, path)), key=key, value=value):
                self._assert_schema_mutation_rejected(path, key, value)

    def test_rejects_unsupported_generator_version(self):
        self._assert_schema_mutation_rejected((), "generator_version", "9.9.9")

    def test_rejects_unknown_and_missing_selection_filter_fields(self):
        mutations = (
            ("unexpected", "value", False),
            ("individual_license", None, True),
            ("measurement_source", None, True),
        )
        for key, value, remove in mutations:
            with self.subTest(key=key, remove=remove):
                self._assert_schema_mutation_rejected(
                    ("sources", "selection_filters"),
                    key,
                    value,
                    remove=remove,
                )

    def test_rejects_noncanonical_or_invalid_utc_timestamp(self):
        for generated_at in (
            "2026-09-02T00:00:00+00:00",
            "2026-09-02t00:00:00z",
            "2026-09-02T00:00:00.000Z",
            "2026-02-30T00:00:00Z",
        ):
            with self.subTest(generated_at=generated_at):
                self._assert_schema_mutation_rejected(
                    (), "generated_at", generated_at
                )

    def test_rejects_noncanonical_genre_keys_and_recording_genres(self):
        payload = valid_payload()
        payload["genres"]["Rock"] = payload["genres"].pop("rock")
        with self.assertRaises(ValueError):
            parse_genre_profile_artifact(with_valid_checksum(payload))

        self._assert_schema_mutation_rejected(
            ("sources", "recordings", 0), "genre", "Rock"
        )

    def test_caches_artifact_for_the_same_path(self):
        path = FIXTURES / "genre_audio_profiles.valid.json"
        self.assertIs(load_genre_profiles(path), load_genre_profiles(path))


if __name__ == "__main__":
    unittest.main()
