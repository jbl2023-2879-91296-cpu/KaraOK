import csv
import math
import shutil
import unittest
import uuid
from contextlib import contextmanager
from dataclasses import replace
from pathlib import Path

from audio_thresholds.derive_genre_profiles import (
    MANIFEST_COLUMNS,
    MeasurementRow,
    analyze_manifest,
    derive_artifact,
    extract_measurement,
    generate_profiles,
    load_measurements,
)
from audio_thresholds.genre_profiles import parse_genre_profile_artifact


FIXTURES = Path(__file__).resolve().parent / "fixtures"
TEST_DIRECTORY = Path(__file__).resolve().parent


@contextmanager
def workspace_temporary_directory():
    path = TEST_DIRECTORY / f"genre-derivation-{uuid.uuid4().hex}"
    path.mkdir()
    try:
        yield path
    finally:
        shutil.rmtree(path)


def analyzer_result(value: float) -> dict:
    return {
        "loudness": {"integrated_lufs": -30.0 + value},
        "bass": {"energy_percentage": 10.0 + value},
        "treble": {"energy_percentage": 1.0 + value},
        "sharpness": {"normalized_score": 0.01 * value},
        "flatness": {"mean": 0.001 * value},
    }


class GenreProfileDerivationTests(unittest.TestCase):
    def test_extracts_exact_karaok_measurement_paths(self):
        analysis = {
            "loudness": {"integrated_lufs": -14.5, "mean_dbfs": 999},
            "bass": {"energy_percentage": 22.5, "rms": 999},
            "treble": {"energy_percentage": 4.5, "rms": 999},
            "sharpness": {"normalized_score": 0.25},
            "flatness": {"mean": 0.025},
        }

        self.assertEqual(
            extract_measurement(analysis),
            {
                "loudness": -14.5,
                "bass": 22.5,
                "treble": 4.5,
                "sharpness": 0.25,
                "flatness": 0.025,
            },
        )

    def test_rejects_non_finite_analyzer_measurement(self):
        analysis = analyzer_result(1.0)
        analysis["bass"]["energy_percentage"] = math.inf

        with self.assertRaisesRegex(ValueError, "bass measurement must be finite"):
            extract_measurement(analysis)

    def test_derives_hand_checked_linear_quartiles(self):
        rows = load_measurements(FIXTURES / "genre_measurements.csv")

        artifact = derive_artifact(rows, minimum_samples=5)

        self.assertEqual(
            artifact["genres"]["rock"]["metrics"]["bass"],
            {
                "lower": 20.0,
                "preferred": 30.0,
                "upper": 40.0,
                "robust_scale": 20.0,
                "unit": "percent",
            },
        )
        parse_genre_profile_artifact(artifact)

    def test_generation_is_deterministic_regardless_of_row_order(self):
        rows = load_measurements(FIXTURES / "genre_measurements.csv")

        self.assertEqual(derive_artifact(rows), derive_artifact(reversed(rows)))

    def test_rejects_cohort_below_minimum(self):
        rows = load_measurements(FIXTURES / "genre_measurements.csv")[:4]

        with self.assertRaisesRegex(ValueError, "at least 5 compatible recordings"):
            derive_artifact(rows)

    def test_rejects_degenerate_metric_with_genre_and_metric(self):
        rows = load_measurements(FIXTURES / "genre_measurements.csv")
        rows = [replace(row, bass=10.0) for row in rows]

        with self.assertRaisesRegex(ValueError, "genre 'rock'.*metric 'bass'"):
            derive_artifact(rows)

    def test_manifest_requires_exact_columns_and_existing_paths(self):
        with workspace_temporary_directory() as root:
            valid_rows = self._manifest_rows(root)

            for name, fieldnames, rows, message in (
                (
                    "extra.csv",
                    (*MANIFEST_COLUMNS, "extra"),
                    [dict(row, extra="unexpected") for row in valid_rows],
                    "exactly",
                ),
                (
                    "missing.csv",
                    MANIFEST_COLUMNS,
                    [dict(valid_rows[0], path="audio/missing.wav"), *valid_rows[1:]],
                    "does not exist",
                ),
            ):
                with self.subTest(name=name):
                    manifest = root / name
                    self._write_manifest(manifest, fieldnames, rows)
                    with self.assertRaisesRegex(ValueError, message):
                        analyze_manifest(manifest, analyzer=analyzer_result)

    def test_manifest_rejects_duplicate_ids_unsupported_genres_and_empty_provenance(self):
        with workspace_temporary_directory() as root:
            valid_rows = self._manifest_rows(root)
            cases = {
                "duplicate recording_id": [
                    valid_rows[0],
                    dict(valid_rows[1], recording_id=valid_rows[0]["recording_id"]),
                    *valid_rows[2:],
                ],
                "Unsupported genre": [dict(valid_rows[0], genre="jazz"), *valid_rows[1:]],
            }
            for field in ("source", "source_version", "license", "citation_url"):
                cases[field] = [dict(valid_rows[0], **{field: "  "}), *valid_rows[1:]]

            for message, rows in cases.items():
                with self.subTest(message=message):
                    manifest = root / f"{len(message)}-{message[:3]}.csv"
                    self._write_manifest(manifest, MANIFEST_COLUMNS, rows)
                    with self.assertRaisesRegex(ValueError, message):
                        analyze_manifest(manifest, analyzer=analyzer_result)

    def test_manifest_rejects_restricted_and_unknown_individual_licenses(self):
        with workspace_temporary_directory() as root:
            for license_name in (
                "Attribution-NonCommercial 4.0",
                "Attribution-NoDerivatives 4.0",
                "Unknown custom license",
            ):
                with self.subTest(license=license_name):
                    rows = self._manifest_rows(root)
                    rows[0]["license"] = license_name
                    manifest = root / f"license-{len(license_name)}.csv"
                    self._write_manifest(manifest, MANIFEST_COLUMNS, rows)
                    with self.assertRaisesRegex(ValueError, "incompatible individual license"):
                        analyze_manifest(manifest, analyzer=analyzer_result)

    def test_manifest_analysis_binds_each_recording_to_full_provenance(self):
        with workspace_temporary_directory() as root:
            rows = self._manifest_rows(root)
            rows[4]["license"] = "Public Domain"
            manifest = root / "manifest.csv"
            self._write_manifest(manifest, MANIFEST_COLUMNS, rows)

            measured = analyze_manifest(
                manifest,
                analyzer=lambda path: analyzer_result(float(path.stem.split("-")[-1]) + 1),
            )
            artifact = derive_artifact(measured)

            self.assertEqual(len(measured), 5)
            self.assertEqual({row.recording_id for row in measured}, {f"rock-{i}" for i in range(5)})
            provenance = {
                (
                    source["source"],
                    source["release"],
                    source["license"],
                    source["citation_url"],
                    recording["recording_id"],
                )
                for source in artifact["sources"]
                for recording in source["recordings"]
            }
            self.assertIn(
                (
                    "Licensed source",
                    "release-v1",
                    "Public Domain",
                    "https://example.test/source",
                    "rock-4",
                ),
                provenance,
            )

    def test_degenerate_generation_writes_failure_report_but_no_artifact(self):
        with workspace_temporary_directory() as root:
            rows = self._manifest_rows(root)
            manifest = root / "manifest.csv"
            output = root / "profiles.json"
            report = root / "report.md"
            self._write_manifest(manifest, MANIFEST_COLUMNS, rows)

            def degenerate_analyzer(path):
                result = analyzer_result(float(path.stem.split("-")[-1]) + 1)
                result["bass"]["energy_percentage"] = 10.0
                return result

            with self.assertRaisesRegex(ValueError, "genre 'rock'.*metric 'bass'"):
                generate_profiles(
                    manifest,
                    output,
                    report,
                    analyzer=degenerate_analyzer,
                )

            self.assertFalse(output.exists())
            self.assertIn("genre 'rock'", report.read_text(encoding="utf-8"))
            self.assertIn("metric 'bass'", report.read_text(encoding="utf-8"))

    @staticmethod
    def _manifest_rows(root: Path) -> list[dict[str, str]]:
        audio = root / "audio"
        audio.mkdir(exist_ok=True)
        rows = []
        for index in range(5):
            path = audio / f"track-{index}.wav"
            path.touch()
            rows.append(
                {
                    "path": str(path.relative_to(root)),
                    "genre": "rock",
                    "source": "Licensed source",
                    "source_version": "release-v1",
                    "license": "CC Attribution",
                    "citation_url": "https://example.test/source",
                    "recording_id": f"rock-{index}",
                }
            )
        return rows

    @staticmethod
    def _write_manifest(path: Path, fieldnames, rows) -> None:
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)


if __name__ == "__main__":
    unittest.main()
