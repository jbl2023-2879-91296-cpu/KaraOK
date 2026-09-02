"""Derive deterministic genre profiles from licensed source recordings."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
import re
import tempfile
from collections import defaultdict
from collections.abc import Callable, Iterable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from .artifact_integrity import canonical_artifact_checksum
from .genre_profiles import (
    INSTRUMENTAL_STATUSES,
    InstrumentalStatus,
    SUPPORTED_METRICS,
    normalize_genre,
    parse_genre_profile_artifact,
)


MANIFEST_COLUMNS = (
    "path",
    "genre",
    "source",
    "source_version",
    "license",
    "citation_url",
    "recording_id",
    "instrumental_status",
)
MEASUREMENT_COLUMNS = (
    "genre",
    "source",
    "source_version",
    "license",
    "citation_url",
    "recording_id",
    "instrumental_status",
    *SUPPORTED_METRICS,
)
FEATURE_PATHS = {
    "loudness": ("loudness", "integrated_lufs"),
    "bass": ("bass", "energy_percentage"),
    "treble": ("treble", "energy_percentage"),
    "sharpness": ("sharpness", "normalized_score"),
    "flatness": ("flatness", "mean"),
}
METRIC_UNITS = {
    "loudness": "LUFS",
    "bass": "percent",
    "treble": "percent",
    "sharpness": "normalized_score",
    "flatness": "ratio",
}
SUPPORTED_GENRES = (
    "rock",
    "pop",
    "ballad",
    "hip-hop",
    "classical",
    "r&b",
    "general",
)
PROFILE_VERSION = "2026.09.1"
GENERATOR_VERSION = "1.0.0"
GENERATED_AT = "2026-09-02T00:00:00Z"
CALCULATION_METHOD = (
    "NumPy linear p25/median/p75; robust_scale=max(p75-p25, "
    "abs(median)*0.05, 1e-9)"
)
COMPATIBLE_FEATURE_NOTES = (
    "All five values were re-extracted from source audio by KaraOK's analyzer; "
    "no external precomputed features were mixed into the profiles."
)
COMPATIBLE_LICENSES = frozenset(
    {
        "attribution",
        "cc attribution",
        "creative commons attribution",
        "public domain",
        "attribution 2 0 uk england",
        "attribution 2 5 canada",
        "attribution 3 0 us",
        "attribution 3 0 united states",
        "attribution 3 0 international",
        "attribution sharealike 3 0 international",
        "attribution share alike 3 0 international",
        "attribution sharealike 3 0 germany",
        "attribution share alike 3 0 germany",
    }
)
GENRE_DISPLAY_NAMES = {
    "rock": "Rock",
    "pop": "Pop",
    "ballad": "Ballad",
    "hip-hop": "Hip-Hop",
    "classical": "Classical",
    "r&b": "R&B",
    "general": "General",
}


@dataclass(frozen=True)
class MeasurementRow:
    genre: str
    source: str
    source_version: str
    license: str
    citation_url: str
    recording_id: str
    instrumental_status: InstrumentalStatus
    loudness: float
    bass: float
    treble: float
    sharpness: float
    flatness: float


def extract_measurement(analysis: Mapping[str, Any]) -> dict[str, float]:
    """Extract KaraOK's exact five profile measurements from analyzer output."""

    extracted: dict[str, float] = {}
    for metric, path in FEATURE_PATHS.items():
        value: Any = analysis
        try:
            for key in path:
                value = value[key]
            number = float(value)
        except (KeyError, TypeError, ValueError) as error:
            raise ValueError(f"{metric} measurement is missing or invalid") from error
        if not math.isfinite(number):
            raise ValueError(f"{metric} measurement must be finite")
        extracted[metric] = number
    return extracted


def _required(row: Mapping[str, Any], field: str) -> str:
    value = row.get(field)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"Manifest row requires non-empty {field}")
    return value.strip()


def _is_compatible_license(value: str) -> bool:
    normalized = re.sub(r"[^a-z0-9]+", " ", value.strip().lower()).strip()
    return normalized in COMPATIBLE_LICENSES


def _validate_provenance(
    *,
    genre: str,
    source: str,
    source_version: str,
    license_name: str,
    citation_url: str,
    recording_id: str,
    instrumental_status: str,
) -> str:
    normalized_genre = normalize_genre(genre)
    if normalized_genre not in SUPPORTED_GENRES:
        raise ValueError(f"Unsupported genre label: {genre!r}")
    for field, value in (
        ("source", source),
        ("source_version", source_version),
        ("license", license_name),
        ("citation_url", citation_url),
        ("recording_id", recording_id),
        ("instrumental_status", instrumental_status),
    ):
        if not value.strip():
            raise ValueError(f"Manifest row requires non-empty {field}")
    if not _is_compatible_license(license_name):
        raise ValueError(f"Recording {recording_id!r} has incompatible individual license {license_name!r}")
    if instrumental_status not in INSTRUMENTAL_STATUSES:
        raise ValueError(
            f"Recording {recording_id!r} has unsupported instrumental_status "
            f"{instrumental_status!r}"
        )
    return normalized_genre


def _measurement_row(
    row: Mapping[str, Any],
    measurements: Mapping[str, Any],
) -> MeasurementRow:
    genre = _validate_provenance(
        genre=str(row["genre"]),
        source=str(row["source"]),
        source_version=str(row["source_version"]),
        license_name=str(row["license"]),
        citation_url=str(row["citation_url"]),
        recording_id=str(row["recording_id"]),
        instrumental_status=str(row["instrumental_status"]),
    )
    numeric: dict[str, float] = {}
    for metric in SUPPORTED_METRICS:
        try:
            value = float(measurements[metric])
        except (KeyError, TypeError, ValueError) as error:
            raise ValueError(f"{metric} measurement is missing or invalid") from error
        if not math.isfinite(value):
            raise ValueError(f"{metric} measurement must be finite")
        numeric[metric] = value
    return MeasurementRow(
        genre=genre,
        source=str(row["source"]).strip(),
        source_version=str(row["source_version"]).strip(),
        license=str(row["license"]).strip(),
        citation_url=str(row["citation_url"]).strip(),
        recording_id=str(row["recording_id"]).strip(),
        instrumental_status=str(row["instrumental_status"]).strip(),
        **numeric,
    )


def load_measurements(path: str | Path) -> list[MeasurementRow]:
    """Load a deterministic test/offline CSV containing already measured rows."""

    measurement_path = Path(path)
    with measurement_path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if tuple(reader.fieldnames or ()) != MEASUREMENT_COLUMNS:
            raise ValueError(
                "Measurement CSV columns must be exactly " + ",".join(MEASUREMENT_COLUMNS)
            )
        raw_rows = list(reader)
    return _validated_measurement_rows(
        [_measurement_row(row, row) for row in raw_rows]
    )


def _validated_measurement_rows(rows: Iterable[MeasurementRow]) -> list[MeasurementRow]:
    validated: list[MeasurementRow] = []
    recording_ids: set[str] = set()
    for row in rows:
        genre = _validate_provenance(
            genre=row.genre,
            source=row.source,
            source_version=row.source_version,
            license_name=row.license,
            citation_url=row.citation_url,
            recording_id=row.recording_id,
            instrumental_status=row.instrumental_status,
        )
        if row.recording_id in recording_ids:
            raise ValueError(f"Manifest has duplicate recording_id {row.recording_id!r}")
        recording_ids.add(row.recording_id)
        values: dict[str, float] = {}
        for metric in SUPPORTED_METRICS:
            value = float(getattr(row, metric))
            if not math.isfinite(value):
                raise ValueError(f"{metric} measurement must be finite")
            values[metric] = value
        validated.append(
            MeasurementRow(
                genre=genre,
                source=row.source.strip(),
                source_version=row.source_version.strip(),
                license=row.license.strip(),
                citation_url=row.citation_url.strip(),
                recording_id=row.recording_id.strip(),
                instrumental_status=row.instrumental_status.strip(),
                **values,
            )
        )
    return sorted(validated, key=lambda row: (row.genre, row.recording_id))


def analyze_manifest(
    path: str | Path,
    *,
    analyzer: Callable[[Path], Mapping[str, Any]] | None = None,
) -> list[MeasurementRow]:
    """Validate a source manifest and analyze every referenced source file."""

    if analyzer is None:
        from audio_engine import analyze_audio

        analyzer = analyze_audio

    manifest_path = Path(path).resolve()
    with manifest_path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if tuple(reader.fieldnames or ()) != MANIFEST_COLUMNS:
            raise ValueError("Manifest columns must be exactly " + ",".join(MANIFEST_COLUMNS))
        raw_rows = list(reader)
    if not raw_rows:
        raise ValueError("Manifest requires at least one recording")

    prepared: list[tuple[dict[str, str], Path]] = []
    recording_ids: set[str] = set()
    for raw_row in raw_rows:
        row = {field: _required(raw_row, field) for field in MANIFEST_COLUMNS}
        try:
            row["genre"] = normalize_genre(row["genre"])
        except ValueError as error:
            raise ValueError(f"Unsupported genre label: {row['genre']!r}") from error
        if row["recording_id"] in recording_ids:
            raise ValueError(f"Manifest has duplicate recording_id {row['recording_id']!r}")
        recording_ids.add(row["recording_id"])
        if not _is_compatible_license(row["license"]):
            raise ValueError(
                f"Recording {row['recording_id']!r} has incompatible individual license "
                f"{row['license']!r}"
            )
        audio_path = (manifest_path.parent / row["path"]).resolve()
        if not audio_path.is_file():
            raise ValueError(
                f"Manifest audio path for {row['recording_id']!r} does not exist: {row['path']}"
            )
        prepared.append((row, audio_path))

    measured = []
    for row, audio_path in sorted(prepared, key=lambda item: (item[0]["genre"], item[0]["recording_id"])):
        measured.append(_measurement_row(row, extract_measurement(analyzer(audio_path))))
    return _validated_measurement_rows(measured)


def _source_metadata(rows: Sequence[MeasurementRow]) -> list[dict[str, Any]]:
    grouped: dict[tuple[str, str, str, str], list[MeasurementRow]] = defaultdict(list)
    for row in rows:
        grouped[(row.source, row.source_version, row.license, row.citation_url)].append(row)

    sources = []
    for (source, release, license_name, citation_url), recordings in sorted(grouped.items()):
        sources.append(
            {
                "source": source,
                "release": release,
                "license": license_name,
                "citation_url": citation_url,
                "selection_filters": {
                    "individual_license": license_name,
                    "measurement_source": "KaraOK audio_engine.analyze_audio",
                },
                "compatible_feature_notes": COMPATIBLE_FEATURE_NOTES,
                "calculation_method": CALCULATION_METHOD,
                "recordings": [
                    {
                        "recording_id": row.recording_id,
                        "genre": row.genre,
                        "instrumental_status": row.instrumental_status,
                    }
                    for row in sorted(recordings, key=lambda item: (item.genre, item.recording_id))
                ],
            }
        )
    return sources


def derive_artifact(
    rows: Iterable[MeasurementRow],
    *,
    minimum_samples: int = 5,
) -> dict[str, Any]:
    """Derive a Task 1-valid artifact from compatible measured recordings."""

    if isinstance(minimum_samples, bool) or not isinstance(minimum_samples, int) or minimum_samples < 1:
        raise ValueError("minimum_samples must be a positive integer")
    ordered_rows = _validated_measurement_rows(rows)
    if not ordered_rows:
        raise ValueError("At least one compatible recording is required")

    cohorts: dict[str, list[MeasurementRow]] = defaultdict(list)
    for row in ordered_rows:
        cohorts[row.genre].append(row)

    genres: dict[str, Any] = {}
    for genre in sorted(cohorts):
        cohort = cohorts[genre]
        if len(cohort) < minimum_samples:
            raise ValueError(
                f"Genre {genre!r} requires at least {minimum_samples} compatible recordings; "
                f"found {len(cohort)}"
            )
        metrics: dict[str, Any] = {}
        for metric in SUPPORTED_METRICS:
            values = np.asarray([getattr(row, metric) for row in cohort], dtype=np.float64)
            lower, preferred, upper = (
                float(value) for value in np.percentile(values, [25, 50, 75], method="linear")
            )
            if not lower < preferred < upper:
                raise ValueError(
                    f"Degenerate profile for genre {genre!r}, metric {metric!r}: "
                    "p25, median, and p75 must be strictly ordered"
                )
            robust_scale = max(upper - lower, abs(preferred) * 0.05, 1e-9)
            metrics[metric] = {
                "lower": lower,
                "preferred": preferred,
                "upper": upper,
                "robust_scale": robust_scale,
                "unit": METRIC_UNITS[metric],
            }
        genres[genre] = {
            "sample_count": len(cohort),
            "corpus_status": (
                "confirmed_instrumental"
                if all(
                    row.instrumental_status == "confirmed_instrumental"
                    for row in cohort
                )
                else "unverified"
            ),
            "metrics": metrics,
        }

    artifact: dict[str, Any] = {
        "schema_version": 1,
        "profile_version": PROFILE_VERSION,
        "generated_at": GENERATED_AT,
        "generator_version": GENERATOR_VERSION,
        "sources": _source_metadata(ordered_rows),
        "genres": genres,
    }
    artifact["artifact_checksum"] = canonical_artifact_checksum(artifact)
    parse_genre_profile_artifact(artifact)
    return artifact


def _manifest_checksum(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _report(artifact: Mapping[str, Any], manifest_checksum: str) -> str:
    genres = artifact["genres"]
    enabled = [genre for genre in SUPPORTED_GENRES if genre in genres]
    disabled = [genre for genre in SUPPORTED_GENRES if genre not in genres]
    disabled_display = _english_list([GENRE_DISPLAY_NAMES[genre] for genre in disabled])
    lines = [
        "# Genre audio profile sources",
        "",
        "This report is generated deterministically by KaraOK's genre profile derivation CLI.",
        "Every enabled target comes from the exact five KaraOK analyzer measurements.",
        "",
        "## Reproducibility",
        "",
        f"- Profile version: `{artifact['profile_version']}`",
        f"- Generator version: `{artifact['generator_version']}`",
        f"- Generated at: `{artifact['generated_at']}`",
        f"- Source manifest SHA-256: `{manifest_checksum}`",
        f"- Artifact checksum: `{artifact['artifact_checksum']}`",
        f"- Calculation: {CALCULATION_METHOD}",
        "",
        "## Genre availability",
        "",
        "| Genre | Status | Instrumental evidence | Compatible recordings |",
        "| --- | --- | --- | ---: |",
    ]
    for genre in SUPPORTED_GENRES:
        if genre in genres:
            evidence = (
                "Confirmed instrumental"
                if genres[genre]["corpus_status"] == "confirmed_instrumental"
                else "Unverified instrumental status"
            )
            lines.append(
                f"| {genre} | Enabled | {evidence} | "
                f"{genres[genre]['sample_count']} |"
            )
        else:
            lines.append(f"| {genre} | Disabled | N/A | 0 |")

    lines.extend(
        [
            "",
            f"Enabled genres: {', '.join(enabled)}.",
            f"Disabled genres: {', '.join(disabled)}.",
            "",
            "## Source provenance",
            "",
            "| Source | Version | Individual license | Citation | Recordings |",
            "| --- | --- | --- | --- | ---: |",
        ]
    )
    for source in artifact["sources"]:
        lines.append(
            f"| {source['source']} | {source['release']} | {source['license']} | "
            f"<{source['citation_url']}> | {len(source['recordings'])} |"
        )

    lines.extend(
        [
            "",
            "## Selection and exclusions",
            "",
            "- Selected rows have an existing audio file, a unique recording ID, a supported genre, and complete source/version/license/citation metadata.",
            "- Accepted individual licenses are Public Domain, Attribution/CC Attribution, and Attribution-ShareAlike variants.",
            "- NonCommercial (NC), NoDerivatives (ND), and unknown/unapproved licenses cause generation to fail; they are never silently included.",
            "- Every selected source file was analyzed by `audio_engine.analyze_audio`; external precomputed features were not used as targets.",
            f"- {disabled_display} remain disabled because the manifest contains no compatible cohort for them.",
            "",
            "## Derived quartiles",
            "",
            "| Genre | Metric | p25 (lower) | Median (preferred) | p75 (upper) | Robust scale | Unit |",
            "| --- | --- | ---: | ---: | ---: | ---: | --- |",
        ]
    )
    for genre in enabled:
        for metric in SUPPORTED_METRICS:
            target = genres[genre]["metrics"][metric]
            lines.append(
                f"| {genre} | {metric} | {target['lower']:.12g} | "
                f"{target['preferred']:.12g} | {target['upper']:.12g} | "
                f"{target['robust_scale']:.12g} | {target['unit']} |"
            )
    return "\n".join(lines) + "\n"


def _failure_report(error: ValueError, manifest_checksum: str) -> str:
    return "\n".join(
        (
            "# Genre audio profile generation failure",
            "",
            f"- Source manifest SHA-256: `{manifest_checksum}`",
            f"- Error: {error}",
            "",
            "No genre profile artifact was written.",
            "",
        )
    )


def _english_list(items: Sequence[str]) -> str:
    if not items:
        return "No genres"
    if len(items) == 1:
        return items[0]
    if len(items) == 2:
        return f"{items[0]} and {items[1]}"
    return f"{', '.join(items[:-1])}, and {items[-1]}"


def _stage_text(path: Path, content: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        newline="\n",
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
        delete=False,
    ) as handle:
        handle.write(content)
        return Path(handle.name)


def _publish_staged_file(staged: Path, destination: Path) -> None:
    os.replace(staged, destination)


def _write_text_atomic(path: Path, content: str) -> None:
    staged = _stage_text(path, content)
    try:
        _publish_staged_file(staged, path)
    finally:
        staged.unlink(missing_ok=True)


def generate_profiles(
    manifest: str | Path,
    output: str | Path,
    report: str | Path,
    *,
    minimum_samples: int = 5,
    analyzer: Callable[[Path], Mapping[str, Any]] | None = None,
) -> dict[str, Any]:
    """Analyze a manifest, validate the full artifact, then write deterministic outputs."""

    manifest_path = Path(manifest).resolve()
    output_path = Path(output)
    report_path = Path(report)
    checksum = _manifest_checksum(manifest_path)
    try:
        artifact = derive_artifact(
            analyze_manifest(manifest_path, analyzer=analyzer),
            minimum_samples=minimum_samples,
        )
        report_text = _report(artifact, checksum)
    except ValueError as error:
        _write_text_atomic(report_path, _failure_report(error, checksum))
        raise

    artifact_text = json.dumps(
        artifact,
        indent=2,
        sort_keys=True,
        ensure_ascii=False,
        allow_nan=False,
    ) + "\n"
    staged_artifact: Path | None = None
    staged_report: Path | None = None
    try:
        staged_artifact = _stage_text(output_path, artifact_text)
        staged_report = _stage_text(report_path, report_text)
        _publish_staged_file(staged_report, report_path)
        staged_report = None
        _publish_staged_file(staged_artifact, output_path)
        staged_artifact = None
    finally:
        if staged_artifact is not None:
            staged_artifact.unlink(missing_ok=True)
        if staged_report is not None:
            staged_report.unlink(missing_ok=True)
    return artifact


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--minimum-samples", type=int, default=5)
    return parser


def main(
    argv: Sequence[str] | None = None,
    *,
    analyzer: Callable[[Path], Mapping[str, Any]] | None = None,
) -> int:
    parser = _parser()
    args = parser.parse_args(argv)
    try:
        generate_profiles(
            args.manifest,
            args.output,
            args.report,
            minimum_samples=args.minimum_samples,
            analyzer=analyzer,
        )
    except (OSError, ValueError) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
