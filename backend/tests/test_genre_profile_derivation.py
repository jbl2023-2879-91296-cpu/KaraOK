import csv
import json
import math
import os
import shutil
import unittest
import uuid
from collections import Counter
from contextlib import contextmanager
from dataclasses import replace
from pathlib import Path
from unittest.mock import patch

from audio_thresholds.derive_genre_profiles import (
    MANIFEST_COLUMNS,
    MeasurementRow,
    analyze_manifest,
    derive_artifact,
    extract_measurement,
    generate_profiles,
    load_measurements,
    main,
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
        self.assertEqual(
            artifact["genres"]["rock"]["corpus_status"],
            "confirmed_instrumental",
        )
        self.assertEqual(
            {
                recording["instrumental_status"]
                for source in artifact["sources"]
                for recording in source["recordings"]
            },
            {"confirmed_instrumental"},
        )
        parse_genre_profile_artifact(artifact)

    def test_generation_is_deterministic_regardless_of_row_order(self):
        rows = load_measurements(FIXTURES / "genre_measurements.csv")

        self.assertEqual(derive_artifact(rows), derive_artifact(reversed(rows)))

    def test_any_unverified_recording_makes_the_genre_corpus_unverified(self):
        rows = load_measurements(FIXTURES / "genre_measurements.csv")
        rows[0] = replace(rows[0], instrumental_status="unverified")

        artifact = derive_artifact(rows)

        self.assertEqual(artifact["genres"]["rock"]["corpus_status"], "unverified")

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
                "Attribution 99.0 Proprietary",
                "Attribution 4.0 International",
                "Attribution 3.0 Mars",
                "Attribution-ShareAlike 3.0 Proprietary",
            ):
                with self.subTest(license=license_name):
                    rows = self._manifest_rows(root)
                    rows[0]["license"] = license_name
                    manifest = root / f"license-{len(license_name)}.csv"
                    self._write_manifest(manifest, MANIFEST_COLUMNS, rows)
                    with self.assertRaisesRegex(ValueError, "incompatible individual license"):
                        analyze_manifest(manifest, analyzer=analyzer_result)

    def test_manifest_accepts_only_the_declared_compatible_license_variants(self):
        compatible = (
            "Attribution",
            "CC Attribution",
            "Creative Commons Attribution",
            "Public Domain",
            "Attribution 2.0 UK: England",
            "Attribution 2.5 Canada",
            "Attribution 3.0 US",
            "Attribution 3.0 United States",
            "Attribution 3.0 International",
            "Attribution-ShareAlike 3.0 International",
            "Attribution-Share Alike 3.0 Germany",
        )
        with workspace_temporary_directory() as root:
            for index, license_name in enumerate(compatible):
                with self.subTest(license=license_name):
                    rows = self._manifest_rows(root)
                    rows[0]["license"] = license_name
                    manifest = root / f"compatible-{index}.csv"
                    self._write_manifest(manifest, MANIFEST_COLUMNS, rows)
                    self.assertEqual(
                        len(analyze_manifest(manifest, analyzer=lambda path: analyzer_result(1.0))),
                        5,
                    )

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

    def test_report_publication_failure_preserves_existing_artifact_and_cleans_staging(self):
        with workspace_temporary_directory() as root:
            manifest = root / "manifest.csv"
            output = root / "profiles.json"
            report = root / "report.md"
            sentinel = b"existing-artifact-must-survive\n"
            output.write_bytes(sentinel)
            self._write_manifest(manifest, MANIFEST_COLUMNS, self._manifest_rows(root))

            real_replace = os.replace

            def fail_report_publication(source, destination):
                if Path(destination) == report:
                    raise OSError("report publication failed")
                real_replace(source, destination)

            with patch(
                "audio_thresholds.derive_genre_profiles.os.replace",
                side_effect=fail_report_publication,
            ):
                with self.assertRaisesRegex(OSError, "report publication failed"):
                    generate_profiles(
                        manifest,
                        output,
                        report,
                        analyzer=lambda path: analyzer_result(
                            float(path.stem.split("-")[-1]) + 1
                        ),
                    )

            self.assertEqual(output.read_bytes(), sentinel)
            self.assertEqual(list(root.glob(".*.tmp")), [])

    def test_cli_is_byte_deterministic_and_analyzes_each_manifest_path_once_per_run(self):
        with workspace_temporary_directory() as root:
            manifest = root / "manifest.csv"
            output = root / "profiles.json"
            report = root / "report.md"
            rows = self._manifest_rows(root)
            self._write_manifest(manifest, MANIFEST_COLUMNS, rows)
            calls: list[Path] = []

            def fake_analyzer(path: Path):
                calls.append(path)
                return analyzer_result(float(path.stem.split("-")[-1]) + 1)

            arguments = (
                "--manifest",
                str(manifest),
                "--output",
                str(output),
                "--report",
                str(report),
                "--minimum-samples",
                "5",
            )
            self.assertEqual(main(arguments, analyzer=fake_analyzer), 0)
            first_artifact = output.read_bytes()
            first_report = report.read_bytes()
            self.assertEqual(main(arguments, analyzer=fake_analyzer), 0)

            expected_paths = Counter((root / row["path"]).resolve() for row in rows)
            self.assertEqual(Counter(calls[:5]), expected_paths)
            self.assertEqual(Counter(calls[5:]), expected_paths)
            self.assertTrue(all(count == 1 for count in expected_paths.values()))
            self.assertEqual(output.read_bytes(), first_artifact)
            self.assertEqual(report.read_bytes(), first_report)

    def test_report_exclusion_narrative_tracks_actual_disabled_genres(self):
        with workspace_temporary_directory() as root:
            manifest = root / "manifest.csv"
            output = root / "profiles.json"
            report = root / "report.md"
            rows = self._manifest_rows(root, genre="pop")
            self._write_manifest(manifest, MANIFEST_COLUMNS, rows)

            generate_profiles(
                manifest,
                output,
                report,
                analyzer=lambda path: analyzer_result(
                    float(path.stem.split("-")[-1]) + 1
                ),
            )

            report_text = report.read_text(encoding="utf-8")
            self.assertIn(
                "Rock, Ballad, Hip-Hop, Classical, R&B, and General remain disabled",
                report_text,
            )
            self.assertNotIn(
                "Ballad, Classical, R&B, and General remain disabled",
                report_text,
            )

    def test_committed_production_artifact_enables_only_real_five_track_cohorts(self):
        artifact_path = Path(__file__).resolve().parents[1] / "audio_thresholds" / "genre_audio_profiles.json"
        artifact = json.loads(artifact_path.read_text(encoding="utf-8"))

        self.assertEqual(set(artifact["genres"]), {"rock", "pop", "hip-hop"})
        self.assertEqual(
            {genre: profile["sample_count"] for genre, profile in artifact["genres"].items()},
            {"rock": 5, "pop": 5, "hip-hop": 5},
        )

    @staticmethod
    def _manifest_rows(root: Path, *, genre: str = "rock") -> list[dict[str, str]]:
        audio = root / "audio"
        audio.mkdir(exist_ok=True)
        rows = []
        for index in range(5):
            path = audio / f"track-{index}.wav"
            path.touch()
            rows.append(
                {
                    "path": str(path.relative_to(root)),
                    "genre": genre,
                    "source": "Licensed source",
                    "source_version": "release-v1",
                    "license": "CC Attribution",
                    "citation_url": "https://example.test/source",
                    "recording_id": f"rock-{index}",
                    "instrumental_status": "confirmed_instrumental",
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
