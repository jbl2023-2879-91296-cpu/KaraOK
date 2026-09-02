# Instrumental Settings Calibration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make KaraOK produce reproducible, conservative recommendations for Volume, Bass, Treble, Sharpness, and Flatness from recorded karaoke instrumental playback, while removing unused database calibration tables.

**Architecture:** Versioned and checksum-validated JSON artifacts own empirical quality ranges, per-genre targets, and researched starting positions. Python owns all validation, confidence, safety, and adjustment calculations; MySQL stores user-owned results plus immutable artifact provenance; Flutter presents typed metadata and requires explicit physical-control confirmation before using researched starting positions.

**Tech Stack:** Python 3, Flask, NumPy, MySQL 8, Dart 3, Flutter, `unittest`, `flutter_test`, PowerShell integration runners

**Spec:** `docs/superpowers/specs/2026-09-03-instrumental-settings-calibration-design.md`

## Global Constraints

- Analyze rendered karaoke instrumental/MIDI playback from the machine's speakers; do not add singer, vocal, feedback, microphone-balance, or microphone-effects logic.
- Keep the five setting keys exactly `volume`, `bass`, `treble`, `sharpness`, and `flatness` in JSON, Python, SQL payloads, and Dart.
- Keep versioned JSON authoritative for empirical thresholds, genre targets, and researched starting priors; keep formulas and safety behavior in Python; use MySQL only for transactional state and provenance.
- Use normalized researched starting positions Volume `40`, Bass `50`, Treble `50`, Sharpness `50`, and Flatness `50` on a `0-100` scale.
- Never silently treat researched starting positions as the user's real current positions; require the user to invoke the action and confirm the physical machine matches.
- A saved amplifier's last applied positions take precedence when the setup screen loads.
- Cap initial changes at `15` normalized points and verification changes at `7.5` normalized points.
- Continue blocking Volume increases when clipping or excessive distortion is detected.
- Current five-recording FMA genre cohorts remain provisional and low-confidence because they are not confirmed instrumental-only.
- Fail closed when any required artifact is missing, malformed, incomplete, non-finite, or checksum-invalid; do not invent fallback targets.
- Remove `genre_preset`, `audio_quality_threshold`, `user_genre_setting`, `audio_analysis_result.preset_id`, and `audio_analysis_result.threshold_id`; do not create replacement tables.
- Do not drop or recreate an unspecified database. Database execution is limited to the integration runner's explicitly named disposable database unless the operator separately chooses to rebuild local development data.
- Do not add live administrator editing of reference artifacts.

## Execution Preflight

The current working tree already contains uncommitted work in backend configuration, the setup screen/tests, and PowerShell runners. Before Task 1, inspect `git status --short` and either commit that existing work on its intended branch or create the execution worktree from a commit that contains it. Do not discard, overwrite, stage, or absorb unrelated user changes into the task commits below.

---

## File Structure Map

### Reference artifacts and loaders

- `backend/audio_thresholds/good_audio_thresholds.json`: generated global empirical ranges plus quality version/checksum.
- `backend/audio_thresholds/artifact_integrity.py`: one canonical SHA-256 implementation shared by all artifact validators.
- `backend/audio_thresholds/scoring.py`: validates and loads the empirical artifact.
- `backend/audio_thresholds/derive_thresholds.py`: deterministically generates the empirical artifact and canonical checksum.
- `backend/audio_thresholds/genre_audio_profiles.json`: provisional per-genre targets plus recording-level instrumental-evidence status.
- `backend/audio_thresholds/genre_profiles.py`: validates genre targets, checksum, and corpus status.
- `backend/audio_thresholds/derive_genre_profiles.py`: carries recording-level instrumental evidence into generated profiles and reports.
- `backend/audio_thresholds/amplifier_control_priors.json`: new researched, normalized five-control starting artifact.
- `backend/audio_thresholds/control_priors.py`: new immutable loader and validator for starting priors.
- `backend/audio_thresholds/__init__.py`: public artifact-loading exports.

### Recommendation and persistence

- `backend/settings_recommendations/models.py`: recommendation request/result provenance types.
- `backend/settings_recommendations/engine.py`: conservative confidence and bounded five-control calculations.
- `backend/karaok/modules/settings_recommendations/service.py`: metadata assembly, guest-token provenance, stored response mapping.
- `backend/karaok/application.py`: empirical scoring provenance, analysis/recommendation inserts, stored-result selects, and rendered-audio validation.
- `database/schema.sql`: authoritative eleven-table schema after retiring legacy tables and adding provenance columns.
- `backend/karaok/modules/admin_data/policy.py`: catalog of only supported database tables.

### Flutter client

- `frontend/lib/features/sound_settings/domain/settings_profile_metadata.dart`: new typed metadata and control-prior contract.
- `frontend/lib/features/sound_settings/data/settings_api.dart`: typed metadata request.
- `frontend/lib/features/sound_settings/domain/settings_recommendation.dart`: genre-profile checksum in recommendation responses.
- `frontend/lib/features/sound_settings/presentation/pages/settings_setup_screen.dart`: explicit researched-start action, physical confirmation, and instrumental-only instructions.
- `frontend/lib/features/assessments/data/audio_staging_service.dart`: clear rejection of symbolic `.mid`/`.midi` files.
- `frontend/lib/features/assessments/presentation/pages/audio_test_screen.dart`: rendered-instrumental recording guidance.

### Tests and documentation

- `backend/tests/test_good_audio_thresholds.py`: empirical artifact version/checksum tests.
- `backend/tests/test_genre_profiles.py`: instrumental evidence contract tests.
- `backend/tests/test_genre_profile_derivation.py`: deterministic evidence propagation tests.
- `backend/tests/test_settings_recommendation_engine.py`: conservative confidence and provenance tests.
- `backend/tests/test_control_priors.py`: new control-prior loader tests.
- `backend/tests/test_settings_recommendation_api.py`: metadata, token, and stored-provenance API tests.
- `backend/tests/test_audio_pipeline.py`: atomic persistence tests for both artifacts.
- `backend/tests/test_audio_validation.py`: rendered-audio/MIDI rejection tests.
- `backend/tests/test_security.py`: authoritative schema and cascade assertions.
- `backend/tests/test_admin_data_api.py`: retired-table catalog assertions.
- `frontend/test/fixtures/settings_profile_metadata_response.json`: shared cross-layer metadata fixture.
- `frontend/test/sound_settings/settings_profile_metadata_test.dart`: typed metadata validation tests.
- `frontend/test/sound_settings/settings_setup_screen_test.dart`: starting-point conversion, precedence, acknowledgement, and copy tests.
- `frontend/test/audio_staging_service_test.dart`: symbolic MIDI rejection test.
- `frontend/integration_test/settings_generation_flow_test.dart`: authenticated Android path through starting point, persistence, application, reload, and verification.
- `tools/run-affected-tests.ps1`: focused suite includes every newly affected backend test.
- `docs/settings-profile-sources.md`, `README.md`, and `CHANGELOG.md`: limitations, provenance, user workflow, and release record.

---

### Task 1: Version and Checksum the Empirical Quality Artifact

**Files:**
- Create: `backend/audio_thresholds/artifact_integrity.py`
- Modify: `backend/audio_thresholds/derive_thresholds.py:35-42,287-405`
- Modify: `backend/audio_thresholds/scoring.py:17-47`
- Modify: `backend/audio_thresholds/good_audio_thresholds.json`
- Modify: `backend/tests/test_good_audio_thresholds.py`

**Interfaces:**
- Produces: `quality_profile_version: str` and `artifact_checksum: str` in every generated/loaded empirical artifact.
- Produces: `canonical_artifact_checksum(data: Mapping[str, Any]) -> str`, computed from canonical JSON after omitting `artifact_checksum`.
- Consumes: existing `derive_threshold_artifact(source_path, *, source_label, cohort_fragment, minimum_samples, bootstrap_iterations, bootstrap_seed) -> dict[str, Any]` and `load_thresholds(path) -> dict[str, Any]` callers without changing their return type.

- [ ] **Step 1: Add failing provenance and tamper tests**

Add these assertions to `GoodAudioThresholdTests`:

```python
def test_empirical_artifact_has_version_and_canonical_checksum(self):
    artifact = derive_threshold_artifact(
        RESULTS_CSV,
        source_label="results/results.csv",
        bootstrap_iterations=200,
    )
    self.assertEqual(artifact["quality_profile_version"], "2026.09.1")
    checksum = artifact["artifact_checksum"]
    unsigned = dict(artifact)
    unsigned.pop("artifact_checksum")
    canonical = json.dumps(
        unsigned, sort_keys=True, separators=(",", ":"), allow_nan=False
    )
    self.assertEqual(
        checksum,
        hashlib.sha256(canonical.encode("utf-8")).hexdigest(),
    )

def test_loader_rejects_tampered_empirical_artifact(self):
    payload = json.loads(THRESHOLD_JSON.read_text(encoding="utf-8"))
    payload["metrics"]["bass"]["median"] += 1
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "tampered.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "checksum"):
            load_thresholds(path)
```

Import `hashlib` at the top of the test.

- [ ] **Step 2: Run the focused test and confirm the contract is missing**

Run:

```powershell
Set-Location backend
py -m unittest tests.test_good_audio_thresholds -v
```

Expected: FAIL because `quality_profile_version` and `artifact_checksum` are absent.

- [ ] **Step 3: Add deterministic provenance generation and validation**

Create `artifact_integrity.py` with the shared implementation:

```python
from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping
from typing import Any


def canonical_artifact_checksum(data: Mapping[str, Any]) -> str:
    unsigned = dict(data)
    unsigned.pop("artifact_checksum", None)
    canonical = json.dumps(
        unsigned, sort_keys=True, separators=(",", ":"), allow_nan=False
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()
```

Define `QUALITY_PROFILE_VERSION = "2026.09.1"` in `derive_thresholds.py` and import the helper there.

Build the existing artifact into a local variable, add
`"quality_profile_version": QUALITY_PROFILE_VERSION`, then set
`artifact["artifact_checksum"] = canonical_artifact_checksum(artifact)` before returning it.

In `scoring.py`, validate both non-empty strings and compare the canonical checksum before validating metrics:

```python
for field in ("quality_profile_version", "algorithm_version", "artifact_checksum"):
    if not isinstance(artifact.get(field), str) or not artifact[field].strip():
        raise ValueError(f"Threshold file is missing {field}.")
expected = canonical_artifact_checksum(artifact)
if artifact["artifact_checksum"] != expected:
    raise ValueError("Threshold artifact checksum does not match canonical content.")
```

Import `canonical_artifact_checksum` from `artifact_integrity.py` in `scoring.py`. In Task 2, replace the private checksum function in `genre_profiles.py` with this same helper so every artifact uses one rule.

- [ ] **Step 4: Regenerate and verify the committed artifact**

Run:

```powershell
Set-Location backend
py -m audio_thresholds.derive_thresholds --source ../results/results.csv --output audio_thresholds/good_audio_thresholds.json
py -m unittest tests.test_good_audio_thresholds -v
```

Expected: PASS, and the unchanged current dataset produces quality profile `2026.09.1` with checksum `e86040c27a2d346c7fda3001ca0fd6cfeabed579ea1f63ed70f8e029dfbb20be`.

- [ ] **Step 5: Commit the empirical provenance contract**

```powershell
git add backend/audio_thresholds/artifact_integrity.py backend/audio_thresholds/derive_thresholds.py backend/audio_thresholds/scoring.py backend/audio_thresholds/good_audio_thresholds.json backend/tests/test_good_audio_thresholds.py
git commit -m "feat: version empirical quality artifact"
```

---

### Task 2: Record Instrumental Evidence and Make Genre Confidence Honest

**Files:**
- Modify: `backend/audio_thresholds/genre_profiles.py`
- Modify: `backend/audio_thresholds/derive_genre_profiles.py`
- Modify: `backend/audio_thresholds/genre_audio_profiles.json`
- Modify: `backend/tests/fixtures/genre_audio_profiles.valid.json`
- Modify: `backend/tests/fixtures/genre_measurements.csv`
- Modify: `backend/tests/test_genre_profiles.py`
- Modify: `backend/tests/test_genre_profile_derivation.py`
- Modify: `backend/settings_recommendations/models.py`
- Modify: `backend/settings_recommendations/engine.py`
- Modify: `backend/karaok/modules/settings_recommendations/service.py`
- Modify: `backend/tests/test_settings_recommendation_engine.py`
- Modify: `backend/tests/test_settings_recommendation_api.py`
- Modify: `docs/settings-profile-sources.md`

**Interfaces:**
- Produces: `GenreProfile.corpus_status: Literal["confirmed_instrumental", "unverified"]`.
- Produces: recording source field `instrumental_status` with the same two allowed values.
- Produces: `RecommendationRequest.profile_checksum: str`, `RecommendationRequest.hardware_response_characterized: bool`, and `SettingsRecommendation.profile_checksum: str` serialized as `profile_checksum`.
- Consumes: Task 1's canonical 64-character SHA-256 convention.

- [ ] **Step 1: Add failing genre-evidence and confidence tests**

Add parser tests that reject missing or inconsistent evidence:

```python
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
```

Add an engine test using a volume-only confidence path:

```python
def profile(*, sample_count=20, missing_metric=None,
            corpus_status="confirmed_instrumental"):
    metrics = {
        metric: MetricTarget(30.0, 40.0, 50.0, 10.0, "test-unit")
        for metric in METRICS
        if metric != missing_metric
    }
    return GenreProfile(
        key="rock",
        sample_count=sample_count,
        corpus_status=corpus_status,
        metrics=MappingProxyType(metrics),
    )


def request(*, scale=None, current=None, measurements=None, safety=None,
            verification=False, profile_checksum="a" * 64,
            hardware_response_characterized=True):
    return RecommendationRequest(
        scale=scale or AmplifierScale(0.0, 100.0, 0.5),
        current=current or KnobSettings(50.0, 50.0, 50.0, 50.0, 50.0),
        measurements=measurements or {metric: 40.0 for metric in METRICS},
        safety=safety or SafetySignals(),
        verification=verification,
        profile_version="test-profile-1",
        profile_checksum=profile_checksum,
        hardware_response_characterized=hardware_response_characterized,
    )


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
```

Add API assertions that `profile_checksum` survives response serialization and the guest verification token round-trip.

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```powershell
Set-Location backend
py -m unittest tests.test_genre_profiles tests.test_genre_profile_derivation tests.test_settings_recommendation_engine tests.test_settings_recommendation_api -v
```

Expected: FAIL because corpus status and recommendation checksum fields are not defined.

- [ ] **Step 3: Extend and validate the genre artifact contract**

Add the status to `GenreProfile`:

```python
INSTRUMENTAL_STATUSES = frozenset({"confirmed_instrumental", "unverified"})

@dataclass(frozen=True)
class GenreProfile:
    key: str
    sample_count: int
    corpus_status: str
    metrics: Mapping[str, MetricTarget]
```

Import Task 1's `canonical_artifact_checksum` and remove the private `_canonical_checksum`. While validating source recordings, require `instrumental_status`, count every recording by genre, and derive the expected genre status as `confirmed_instrumental` only when all recordings are confirmed. Reject any declared `genres.<genre>.corpus_status` that disagrees with the recording evidence.

Extend `MeasurementRow`, `MANIFEST_COLUMNS`, `MEASUREMENT_COLUMNS`, CSV parsing, source emission, and report generation in `derive_genre_profiles.py`. Generated recording entries must have this exact shape:

```python
{
    "recording_id": row.recording_id,
    "genre": row.genre,
    "instrumental_status": row.instrumental_status,
}
```

Generated genre entries must contain:

```python
"corpus_status": (
    "confirmed_instrumental"
    if all(row.instrumental_status == "confirmed_instrumental" for row in cohort)
    else "unverified"
)
```

- [ ] **Step 4: Mark the existing FMA artifact as unverified without changing its targets**

Add `"corpus_status": "unverified"` to each of the three genre objects and `"instrumental_status": "unverified"` to every source recording. Preserve all numeric targets and set the canonical artifact checksum to:

```text
8b87b9f1106bab8dab4978e4590e84c9bb294400a0d60ce5263e196f44701b61
```

Update `docs/settings-profile-sources.md` so each enabled genre visibly says `Unverified instrumental status` and explains that the profiles remain provisional until regenerated from licensed, genre-representative instrumental or rendered-MIDI audio.

- [ ] **Step 5: Carry checksum provenance and corpus status through the engine**

Add `profile_checksum` and `hardware_response_characterized: bool = False` to `RecommendationRequest`. Add `profile_checksum` to `SettingsRecommendation`, validate it as exactly 64 lowercase hexadecimal characters, and emit it from `to_dict()`. Pass `artifact.artifact_checksum` from `build_recommendation()` and `_unavailable_recommendation()`; keep `hardware_response_characterized=False` until a saved amplifier has measured response-curve data.

Update confidence calculation with the explicit corpus penalty:

```python
if profile.sample_count < 20:
    score -= 1
if profile.corpus_status != "confirmed_instrumental":
    score -= 1
if not request.hardware_response_characterized:
    score -= 1
if knob in CROSS_COUPLED_KNOBS:
    score -= 1
```

Add `profile_checksum` to `GUEST_TOKEN_CLAIMS`, `GuestVerificationContext`, token issuance, token parsing, and verification-continuity checks. A verification request must reject a token whose profile version or checksum differs from the currently loaded artifact.

- [ ] **Step 6: Run all genre and engine tests**

Run:

```powershell
Set-Location backend
py -m unittest tests.test_genre_profiles tests.test_genre_profile_derivation tests.test_settings_recommendation_engine tests.test_settings_recommendation_api -v
```

Expected: PASS. The committed FMA profiles report low overall confidence, while a test fixture with at least 20 confirmed-instrumental recordings can still reach higher confidence when other penalties are absent.

- [ ] **Step 7: Commit evidence-aware recommendations**

```powershell
git add backend/audio_thresholds/genre_profiles.py backend/audio_thresholds/derive_genre_profiles.py backend/audio_thresholds/genre_audio_profiles.json backend/tests/fixtures/genre_audio_profiles.valid.json backend/tests/fixtures/genre_measurements.csv backend/tests/test_genre_profiles.py backend/tests/test_genre_profile_derivation.py backend/settings_recommendations/models.py backend/settings_recommendations/engine.py backend/karaok/modules/settings_recommendations/service.py backend/tests/test_settings_recommendation_engine.py backend/tests/test_settings_recommendation_api.py docs/settings-profile-sources.md
git commit -m "feat: qualify genre profile evidence"
```

---

### Task 3: Add Researched Control Priors and Metadata Contract

**Files:**
- Create: `backend/audio_thresholds/amplifier_control_priors.json`
- Create: `backend/audio_thresholds/control_priors.py`
- Create: `backend/tests/test_control_priors.py`
- Create: `frontend/test/fixtures/settings_profile_metadata_response.json`
- Modify: `backend/audio_thresholds/__init__.py`
- Modify: `backend/karaok/modules/settings_recommendations/service.py:687-692`
- Modify: `backend/tests/test_settings_recommendation_api.py:211-222`

**Interfaces:**
- Produces: `ControlPriorArtifact(prior_version, artifact_checksum, normalized_scale, positions, requires_physical_confirmation)`.
- Produces: `load_control_priors(path: str | Path = DEFAULT_CONTROL_PRIOR_PATH) -> ControlPriorArtifact`.
- Produces: expanded `GET /api/settings-profile-metadata` response used by Tasks 5 and 6.
- Consumes: Task 1 quality version/checksum and Task 2 genre version/checksum.

- [ ] **Step 1: Write failing loader and metadata tests**

Create `backend/tests/test_control_priors.py` with tests for exact keys, finite range, checksum tampering, unknown keys, missing citations, and cached repeat loads. The primary happy-path assertion is:

```python
artifact = load_control_priors()
self.assertEqual(artifact.prior_version, "2026.09.1")
self.assertEqual(
    artifact.positions,
    {"volume": 40.0, "bass": 50.0, "treble": 50.0,
     "sharpness": 50.0, "flatness": 50.0},
)
self.assertTrue(artifact.requires_physical_confirmation)
```

Replace the metadata API expectation with this exact key set:

```python
self.assertEqual(
    set(response.get_json()),
    {
        "profile_version", "profile_checksum", "quality_profile_version",
        "quality_profile_checksum", "enabled_genres", "control_priors",
    },
)
```

Use the same response body in `frontend/test/fixtures/settings_profile_metadata_response.json` so Python and Dart test one contract.

The shared fixture content is:

```json
{
  "profile_version": "2026.09.1",
  "profile_checksum": "8b87b9f1106bab8dab4978e4590e84c9bb294400a0d60ce5263e196f44701b61",
  "quality_profile_version": "2026.09.1",
  "quality_profile_checksum": "e86040c27a2d346c7fda3001ca0fd6cfeabed579ea1f63ed70f8e029dfbb20be",
  "enabled_genres": ["hip-hop", "pop", "rock"],
  "control_priors": {
    "prior_version": "2026.09.1",
    "artifact_checksum": "22f1dde7455dd1d6d6c83c54a00d885e6bd3fecd89a8b05f6874bf88a774be71",
    "normalized_scale": {"minimum": 0.0, "maximum": 100.0},
    "positions": {"volume": 40.0, "bass": 50.0, "treble": 50.0, "sharpness": 50.0, "flatness": 50.0},
    "requires_physical_confirmation": true
  }
}
```

- [ ] **Step 2: Run tests and verify the artifact is unavailable**

Run:

```powershell
Set-Location backend
py -m unittest tests.test_control_priors tests.test_settings_recommendation_api -v
```

Expected: FAIL because `control_priors.py`, its JSON artifact, and expanded metadata do not exist.

- [ ] **Step 3: Create the immutable control-prior artifact and loader**

Create `amplifier_control_priors.json` with this exact semantic content and checksum:

```json
{
  "schema_version": 1,
  "prior_version": "2026.09.1",
  "normalized_scale": {"minimum": 0.0, "maximum": 100.0},
  "positions": {"volume": 40.0, "bass": 50.0, "treble": 50.0, "sharpness": 50.0, "flatness": 50.0},
  "requires_physical_confirmation": true,
  "assumptions": [
    "Volume begins below midpoint to preserve headroom; it is not a universal optimum.",
    "Bass and Treble use the neutral midpoint documented for conventional tone controls.",
    "Sharpness and Flatness use neutral project assumptions pending hardware response data."
  ],
  "sources": [
    {"title": "ITU-R BS.1770-5", "url": "https://www.itu.int/rec/R-REC-BS.1770-5-202311-I/en", "supports": "Programme loudness and true-peak measurement concepts."},
    {"title": "Yamaha R-N1000A tone control manual", "url": "https://manual.yamaha.com/av/22/rn1000a/en-US/8393117835.html", "supports": "Bass and Treble midpoint is flat response."},
    {"title": "librosa spectral_flatness", "url": "https://librosa.org/doc/main/generated/librosa.feature.spectral_flatness.html", "supports": "Spectral flatness definition."},
    {"title": "MathWorks acousticSharpness", "url": "https://www.mathworks.com/help/audio/ref/acousticsharpness.html", "supports": "Standards-based sharpness context; KaraOK's score is not acum."}
  ],
  "artifact_checksum": "22f1dde7455dd1d6d6c83c54a00d885e6bd3fecd89a8b05f6874bf88a774be71"
}
```

Implement `control_priors.py` with immutable dataclasses/mapping proxies and the same canonical checksum rule. Reject booleans as numbers, non-finite values, any position outside `0-100`, any key set other than the five controls, normalized bounds other than `0` and `100`, empty sources/assumptions, and `requires_physical_confirmation != True`.

Use this public shape and parsing flow:

```python
from __future__ import annotations

import json
import math
import re
from collections.abc import Mapping
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from types import MappingProxyType
from typing import Any

from .artifact_integrity import canonical_artifact_checksum

CONTROL_NAMES = ("volume", "bass", "treble", "sharpness", "flatness")
ARTIFACT_KEYS = {
    "schema_version", "prior_version", "normalized_scale", "positions",
    "requires_physical_confirmation", "assumptions", "sources",
    "artifact_checksum",
}
DEFAULT_CONTROL_PRIOR_PATH = Path(__file__).with_name(
    "amplifier_control_priors.json"
)


@dataclass(frozen=True)
class ControlPriorArtifact:
    prior_version: str
    artifact_checksum: str
    normalized_scale: Mapping[str, float]
    positions: Mapping[str, float]
    requires_physical_confirmation: bool

    def to_metadata(self) -> dict[str, Any]:
        return {
            "prior_version": self.prior_version,
            "artifact_checksum": self.artifact_checksum,
            "normalized_scale": dict(self.normalized_scale),
            "positions": dict(self.positions),
            "requires_physical_confirmation": self.requires_physical_confirmation,
        }


def _finite(value: Any, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{field} must be a finite number")
    number = float(value)
    if not math.isfinite(number):
        raise ValueError(f"{field} must be a finite number")
    return number


def parse_control_priors(data: Mapping[str, Any]) -> ControlPriorArtifact:
    if set(data) != ARTIFACT_KEYS:
        raise ValueError("Control-prior artifact fields do not match schema")
    if data.get("schema_version") != 1:
        raise ValueError("Unsupported control-prior schema_version; expected 1")
    version = data.get("prior_version")
    checksum = data.get("artifact_checksum")
    if not isinstance(version, str) or not version.strip():
        raise ValueError("Control priors require prior_version")
    if not isinstance(checksum, str) or re.fullmatch(r"[0-9a-f]{64}", checksum) is None:
        raise ValueError("Control priors require a SHA-256 artifact_checksum")
    if checksum != canonical_artifact_checksum(data):
        raise ValueError("Control-prior artifact checksum does not match canonical content")
    scale = data.get("normalized_scale")
    positions = data.get("positions")
    if not isinstance(scale, Mapping) or set(scale) != {"minimum", "maximum"}:
        raise ValueError("Control priors require an exact normalized_scale")
    parsed_scale = {key: _finite(scale[key], f"normalized_scale.{key}") for key in scale}
    if parsed_scale != {"minimum": 0.0, "maximum": 100.0}:
        raise ValueError("Control-prior normalized_scale must be 0-100")
    if not isinstance(positions, Mapping) or set(positions) != set(CONTROL_NAMES):
        raise ValueError("Control priors require exactly all five controls")
    parsed_positions = {
        name: _finite(positions[name], f"positions.{name}") for name in CONTROL_NAMES
    }
    if any(value < 0.0 or value > 100.0 for value in parsed_positions.values()):
        raise ValueError("Control-prior positions must be within 0-100")
    if data.get("requires_physical_confirmation") is not True:
        raise ValueError("Control priors must require physical confirmation")
    for field in ("assumptions", "sources"):
        value = data.get(field)
        if not isinstance(value, list) or not value:
            raise ValueError(f"Control priors require non-empty {field}")
    if any(not isinstance(item, str) or not item.strip() for item in data["assumptions"]):
        raise ValueError("Control-prior assumptions must be non-empty strings")
    for source in data["sources"]:
        if not isinstance(source, Mapping) or set(source) != {"title", "url", "supports"}:
            raise ValueError("Control-prior sources must match the source schema")
        if any(not isinstance(source[key], str) or not source[key].strip()
               for key in ("title", "url", "supports")):
            raise ValueError("Control-prior source fields must be non-empty strings")
    return ControlPriorArtifact(
        prior_version=version.strip(),
        artifact_checksum=checksum,
        normalized_scale=MappingProxyType(parsed_scale),
        positions=MappingProxyType(parsed_positions),
        requires_physical_confirmation=True,
    )


@lru_cache(maxsize=None)
def _load_control_priors(path: str) -> ControlPriorArtifact:
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError) as error:
        raise ValueError(f"Control-prior artifact is unavailable: {error}") from error
    if not isinstance(data, Mapping):
        raise ValueError("Control-prior artifact must be an object")
    return parse_control_priors(data)


def load_control_priors(
    path: str | Path = DEFAULT_CONTROL_PRIOR_PATH,
) -> ControlPriorArtifact:
    return _load_control_priors(str(Path(path).resolve()))
```

Also validate that each assumption is a non-empty string and each source has non-empty `title`, `url`, and `supports` strings. Export `ControlPriorArtifact`, `load_control_priors`, and a cache-clear helper from `audio_thresholds.__init__`.

- [ ] **Step 4: Assemble the public metadata response**

Update `get_profile_metadata()` to load all three artifacts and return:

```python
genre = load_genre_profiles()
quality = load_thresholds()
priors = load_control_priors()
return {
    "profile_version": genre.profile_version,
    "profile_checksum": genre.artifact_checksum,
    "quality_profile_version": quality["quality_profile_version"],
    "quality_profile_checksum": quality["artifact_checksum"],
    "enabled_genres": sorted(genre.genres),
    "control_priors": priors.to_metadata(),
}
```

`to_metadata()` returns `prior_version`, `artifact_checksum`, `normalized_scale`, `positions`, and `requires_physical_confirmation`; research citations stay in the versioned backend artifact and documentation rather than inflating every mobile response.

- [ ] **Step 5: Run the loader and API contract tests**

Run:

```powershell
Set-Location backend
py -m unittest tests.test_control_priors tests.test_settings_recommendation_api -v
```

Expected: PASS, including checksum tamper rejection and the shared metadata fixture.

- [ ] **Step 6: Commit researched priors and metadata**

```powershell
git add backend/audio_thresholds/amplifier_control_priors.json backend/audio_thresholds/control_priors.py backend/audio_thresholds/__init__.py backend/karaok/modules/settings_recommendations/service.py backend/tests/test_control_priors.py backend/tests/test_settings_recommendation_api.py frontend/test/fixtures/settings_profile_metadata_response.json
git commit -m "feat: expose researched amplifier priors"
```

---

### Task 4: Simplify the Schema and Persist Artifact Provenance

**Files:**
- Modify: `database/schema.sql:55-85,121-179,205-243,297-319`
- Modify: `backend/karaok/application.py:106-126,571-592,706-880,1954-1988,2485-2562`
- Modify: `backend/karaok/modules/settings_recommendations/service.py:603-672,863-899`
- Modify: `backend/karaok/modules/admin_data/policy.py:27-73`
- Modify: `backend/tests/test_security.py:301-431`
- Modify: `backend/tests/test_admin_data_api.py:60-105`
- Modify: `backend/tests/test_audio_pipeline.py`
- Modify: `backend/tests/test_settings_recommendation_api.py`

**Interfaces:**
- Produces: `audio_analysis_result.quality_profile_version VARCHAR(30) NOT NULL` and `quality_profile_checksum CHAR(64) NOT NULL`.
- Produces: `settings_recommendation.genre_profile_checksum CHAR(64) NOT NULL`.
- Produces: stored API fields `quality_profile_version`, `quality_profile_checksum`, and recommendation `profile_checksum`.
- Consumes: Task 1 empirical provenance and Task 2 recommendation checksum.

- [ ] **Step 1: Write failing authoritative-schema tests**

Add exact negative and positive assertions:

```python
for retired_table in ("genre_preset", "audio_quality_threshold", "user_genre_setting"):
    self.assertNotIn(f"CREATE TABLE IF NOT EXISTS {retired_table}", schema)
self.assertEqual(schema.count("CREATE TABLE IF NOT EXISTS "), 11)

analysis_table = schema.split(
    "CREATE TABLE IF NOT EXISTS audio_analysis_result", 1
)[1].split("CREATE TABLE IF NOT EXISTS amplifier_profile", 1)[0]
self.assertNotIn("preset_id", analysis_table)
self.assertNotIn("threshold_id", analysis_table)
self.assertIn("quality_profile_version VARCHAR(30) NOT NULL", analysis_table)
self.assertIn("quality_profile_checksum CHAR(64) NOT NULL", analysis_table)

recommendation_table = schema.split(
    "CREATE TABLE IF NOT EXISTS settings_recommendation", 1
)[1].split("CREATE TABLE IF NOT EXISTS refresh_token", 1)[0]
self.assertIn("genre_profile_checksum CHAR(64) NOT NULL", recommendation_table)

application_source = (
    Path(__file__).resolve().parents[1] / "karaok" / "application.py"
).read_text(encoding="utf-8")
self.assertNotIn("FROM genre_preset", application_source)
self.assertNotIn("threshold_id, preset_id", application_source)
```

Replace the admin legacy-table test with:

```python
def test_retired_reference_tables_are_not_advertised(self):
    for table in ("genre_preset", "audio_quality_threshold", "user_genre_setting"):
        with self.subTest(table=table):
            with self.assertRaises(ValueError):
                service.table_policy(table)
```

Add persistence assertions that both checksum values appear in insert parameters and that failure rolls back the analysis and recommendation together. Retain explicit assertions for `ON DELETE CASCADE` from user to assessment/amplifier, assessment to analysis/upload/recommendation, and amplifier to recommendation.

- [ ] **Step 2: Run schema, admin, and persistence tests to confirm failure**

Run:

```powershell
Set-Location backend
py -m unittest tests.test_security tests.test_admin_data_api tests.test_audio_pipeline tests.test_settings_recommendation_api -v
```

Expected: FAIL because legacy schema/policies remain and provenance columns are absent.

- [ ] **Step 3: Update the single authoritative schema**

Delete the three complete legacy `CREATE TABLE` blocks. Remove `threshold_id`, `preset_id`, `fk_result_threshold`, and `fk_result_preset` from `audio_analysis_result`. Add:

```sql
quality_profile_version VARCHAR(30) NOT NULL,
quality_profile_checksum CHAR(64) NOT NULL,
```

Add this after `genre_profile_version` in `settings_recommendation`:

```sql
genre_profile_checksum CHAR(64) NOT NULL,
```

Do not add a migration file and do not run this schema against an unspecified database. Retain all eleven business/security/log tables and their existing ownership/cascade constraints.

- [ ] **Step 4: Remove legacy policy and persistence lookups**

Delete the three table policies from `TABLE_POLICIES`. In `persist_audio_analysis()`, delete the `genre_preset` lookup and insert analysis results directly with provenance:

```python
quality_profile_version = str(empirical["quality_profile_version"])
quality_profile_checksum = str(empirical["quality_profile_checksum"])
cursor.execute(
    """INSERT INTO audio_analysis_result
       (assessment_id, quality_score, noise_level, distortion_level,
        bass, treble, loudness, sharpness, flatness, empirical_status,
        worst_feature_status, worst_features, empirical_details,
        scoring_algorithm_version, quality_profile_version,
        quality_profile_checksum, reference_recording_count,
        waveform_path, spectrogram_path)
       VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
               %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
    (
        assessment_id,
        quality_score,
        noise_level,
        distortion_level,
        bass,
        treble,
        loudness,
        sharpness,
        flatness,
        empirical_status,
        worst_feature_status,
        worst_features_json,
        empirical_details_json,
        algorithm_version,
        quality_profile_version,
        quality_profile_checksum,
        reference_recording_count,
        waveform_path,
        spectrogram_path,
    ),
)
```

- [ ] **Step 5: Attach provenance to scoring, recommendations, and stored responses**

In `_score_analyzer_output()`, add:

```python
empirical["quality_profile_version"] = thresholds["quality_profile_version"]
empirical["quality_profile_checksum"] = thresholds["artifact_checksum"]
```

Add `genre_profile_checksum` to the recommendation insert, select constants, row conversion, and response as `profile_checksum`. Add both quality fields to stored audio-analysis selects/responses.

For the manual `create_audio_test()` helper, load the validated empirical artifact and persist its algorithm version, profile version, and checksum instead of inserting retired ID columns:

```python
thresholds = load_thresholds()
cursor.execute(
    """INSERT INTO audio_analysis_result
       (assessment_id, quality_score, noise_level, distortion_level,
        scoring_algorithm_version, quality_profile_version,
        quality_profile_checksum)
       VALUES (%s, %s, %s, %s, %s, %s, %s)""",
    (
        test_id, score, noise, distortion, thresholds["algorithm_version"],
        thresholds["quality_profile_version"], thresholds["artifact_checksum"],
    ),
)
```

- [ ] **Step 6: Run backend persistence and full schema tests**

Run:

```powershell
Set-Location backend
py -m unittest tests.test_security tests.test_admin_data_api tests.test_audio_pipeline tests.test_settings_recommendation_api -v
py -m unittest discover -s tests -p "test_*.py"
```

Expected: PASS. SQL mocks show one commit only after both analysis and recommendation inserts; all error paths roll back.

- [ ] **Step 7: Commit schema simplification and provenance**

```powershell
git add database/schema.sql backend/karaok/application.py backend/karaok/modules/settings_recommendations/service.py backend/karaok/modules/admin_data/policy.py backend/tests/test_security.py backend/tests/test_admin_data_api.py backend/tests/test_audio_pipeline.py backend/tests/test_settings_recommendation_api.py
git commit -m "refactor: store artifact provenance without legacy tables"
```

---

### Task 5: Add Typed Flutter Metadata and Recommendation Provenance

**Files:**
- Create: `frontend/lib/features/sound_settings/domain/settings_profile_metadata.dart`
- Create: `frontend/test/sound_settings/settings_profile_metadata_test.dart`
- Modify: `frontend/lib/features/sound_settings/data/settings_api.dart:1-15`
- Modify: `frontend/lib/features/sound_settings/domain/settings_recommendation.dart`
- Modify: `frontend/lib/features/sound_settings/presentation/pages/settings_setup_screen.dart:62-162`
- Modify: `frontend/test/sound_settings/settings_models_test.dart`
- Modify: `frontend/test/sound_settings/settings_setup_screen_test.dart:450-465`
- Modify: `frontend/test/fixtures/settings_recommendation_response.json`

**Interfaces:**
- Produces: `SettingsProfileMetadata.fromJson(Map<String, dynamic>)`.
- Produces: `ControlPriors.toScale(AmplifierScale scale) -> KnobSettings`.
- Produces: `SettingsApi.getProfileMetadata() -> Future<SettingsProfileMetadata>`.
- Consumes: Task 3's exact metadata fixture and Task 4's recommendation `profile_checksum`.

- [ ] **Step 1: Write failing Dart contract tests**

Create a test that parses the shared fixture and verifies exact conversion:

```dart
test('profile metadata parses all artifact provenance and five priors', () {
  final json = jsonDecode(
    File('test/fixtures/settings_profile_metadata_response.json')
        .readAsStringSync(),
  ) as Map<String, dynamic>;
  final metadata = SettingsProfileMetadata.fromJson(json);
  expect(metadata.enabledGenres, ['hip-hop', 'pop', 'rock']);
  expect(metadata.profileChecksum, hasLength(64));
  expect(metadata.qualityProfileChecksum, hasLength(64));
  expect(metadata.controlPriors.requiresPhysicalConfirmation, isTrue);
  expect(
    metadata.controlPriors.toScale(
      const AmplifierScale(minimum: 0, maximum: 10, step: 0.5),
    ),
    const KnobSettings(
      volume: 4, bass: 5, treble: 5, sharpness: 5, flatness: 5,
    ),
  );
});
```

Add rejection cases for a missing checksum, duplicate/empty genre, a non-`0-100` normalized source scale, missing knob, non-finite position, and `requires_physical_confirmation: false`.

Update recommendation model tests to require a lowercase 64-character `profile_checksum`.

- [ ] **Step 2: Run the Flutter model tests and confirm failure**

Run:

```powershell
Set-Location frontend
flutter test test/sound_settings/settings_profile_metadata_test.dart test/sound_settings/settings_models_test.dart --reporter expanded
```

Expected: FAIL because the typed metadata model and recommendation checksum do not exist.

- [ ] **Step 3: Implement strict typed metadata models**

Create immutable `ControlPriors` and `SettingsProfileMetadata` classes. Validate exact five-control keys and provenance strings. Conversion must reuse `AmplifierScale.denormalize`:

```dart
String _requiredString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value.trim();
}

String _checksum(Object? value, String field) {
  final checksum = _requiredString(value, field);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum)) {
    throw FormatException('$field must be a lowercase SHA-256 value.');
  }
  return checksum;
}

Map<String, dynamic> _object(Object? value, String field) {
  if (value is! Map) throw FormatException('$field must be an object.');
  return Map<String, dynamic>.from(value);
}

bool _hasExactKeys(Map<String, dynamic> json, Set<String> expected) {
  final actual = json.keys.toSet();
  return actual.length == expected.length && actual.containsAll(expected);
}

class ControlPriors {
  const ControlPriors({
    required this.priorVersion,
    required this.artifactChecksum,
    required this.positions,
    required this.requiresPhysicalConfirmation,
  });

  factory ControlPriors.fromJson(Map<String, dynamic> json) {
    if (!_hasExactKeys(json, const {
      'prior_version',
      'artifact_checksum',
      'normalized_scale',
      'positions',
      'requires_physical_confirmation',
    })) {
      throw const FormatException('Control-prior fields do not match schema.');
    }
    final scale = _object(json['normalized_scale'], 'normalized_scale');
    if (scale['minimum'] != 0 && scale['minimum'] != 0.0 ||
        scale['maximum'] != 100 && scale['maximum'] != 100.0) {
      throw const FormatException('Control priors must use a 0-100 scale.');
    }
    if (json['requires_physical_confirmation'] is! bool ||
        json['requires_physical_confirmation'] != true) {
      throw const FormatException('Control priors must require confirmation.');
    }
    final positions = KnobSettings.fromJson(
      _object(json['positions'], 'positions'),
      scale: const AmplifierScale(minimum: 0, maximum: 100, step: 1),
    );
    return ControlPriors(
      priorVersion: _requiredString(json['prior_version'], 'prior_version'),
      artifactChecksum: _checksum(
        json['artifact_checksum'],
        'artifact_checksum',
      ),
      positions: positions,
      requiresPhysicalConfirmation: true,
    );
  }

  final String priorVersion;
  final String artifactChecksum;
  final KnobSettings positions;
  final bool requiresPhysicalConfirmation;

KnobSettings toScale(AmplifierScale scale) => KnobSettings(
  volume: scale.denormalize(positions.volume),
  bass: scale.denormalize(positions.bass),
  treble: scale.denormalize(positions.treble),
  sharpness: scale.denormalize(positions.sharpness),
  flatness: scale.denormalize(positions.flatness),
);
}

class SettingsProfileMetadata {
  const SettingsProfileMetadata({
    required this.profileVersion,
    required this.profileChecksum,
    required this.qualityProfileVersion,
    required this.qualityProfileChecksum,
    required this.enabledGenres,
    required this.controlPriors,
  });

  factory SettingsProfileMetadata.fromJson(Map<String, dynamic> json) {
    if (!_hasExactKeys(json, const {
      'profile_version',
      'profile_checksum',
      'quality_profile_version',
      'quality_profile_checksum',
      'enabled_genres',
      'control_priors',
    })) {
      throw const FormatException('Settings metadata fields do not match schema.');
    }
    final rawGenres = json['enabled_genres'];
    if (rawGenres is! List || rawGenres.any((value) => value is! String)) {
      throw const FormatException('enabled_genres must be a string list.');
    }
    final genres = rawGenres.cast<String>().map((value) => value.trim()).toList();
    if (genres.isEmpty || genres.any((value) => value.isEmpty) ||
        genres.toSet().length != genres.length) {
      throw const FormatException('enabled_genres must be non-empty and unique.');
    }
    return SettingsProfileMetadata(
      profileVersion: _requiredString(json['profile_version'], 'profile_version'),
      profileChecksum: _checksum(json['profile_checksum'], 'profile_checksum'),
      qualityProfileVersion: _requiredString(
        json['quality_profile_version'],
        'quality_profile_version',
      ),
      qualityProfileChecksum: _checksum(
        json['quality_profile_checksum'],
        'quality_profile_checksum',
      ),
      enabledGenres: List.unmodifiable(genres),
      controlPriors: ControlPriors.fromJson(
        _object(json['control_priors'], 'control_priors'),
      ),
    );
  }

  final String profileVersion;
  final String profileChecksum;
  final String qualityProfileVersion;
  final String qualityProfileChecksum;
  final List<String> enabledGenres;
  final ControlPriors controlPriors;
}
```

Store the prior positions as `KnobSettings` on their normalized `0-100` scale. Validate SHA-256 strings with `RegExp(r'^[0-9a-f]{64}$')`.

- [ ] **Step 4: Make the API and setup loader consume typed metadata**

Change the API method to:

```dart
Future<SettingsProfileMetadata> getProfileMetadata() async =>
    SettingsProfileMetadata.fromJson(
      await _client.getSettingsProfileMetadata(),
    );
```

In `SettingsSetupScreen._load()`, set `_metadata` and `_enabledGenres` from the typed object. Update `_FakeSettingsApi` to return `Future<SettingsProfileMetadata>` built from the shared valid response. Preserve current disabled/retry behavior.

- [ ] **Step 5: Parse recommendation provenance**

Add `profileChecksum` to `SettingsRecommendation`, require it in `fromJson`, include it in `toJson`, and update the cross-layer recommendation fixture with the checksum produced by Task 2.

- [ ] **Step 6: Run model and existing screen suites**

Run:

```powershell
Set-Location frontend
dart format lib/features/sound_settings/domain/settings_profile_metadata.dart lib/features/sound_settings/data/settings_api.dart lib/features/sound_settings/domain/settings_recommendation.dart lib/features/sound_settings/presentation/pages/settings_setup_screen.dart test/sound_settings/settings_profile_metadata_test.dart test/sound_settings/settings_models_test.dart test/sound_settings/settings_setup_screen_test.dart
flutter test test/sound_settings --reporter compact
```

Expected: PASS with the setup screen behavior unchanged except for stricter response validation.

- [ ] **Step 7: Commit the typed client contract**

```powershell
git add frontend/lib/features/sound_settings/domain/settings_profile_metadata.dart frontend/lib/features/sound_settings/data/settings_api.dart frontend/lib/features/sound_settings/domain/settings_recommendation.dart frontend/lib/features/sound_settings/presentation/pages/settings_setup_screen.dart frontend/test/sound_settings/settings_profile_metadata_test.dart frontend/test/sound_settings/settings_models_test.dart frontend/test/sound_settings/settings_setup_screen_test.dart frontend/test/fixtures/settings_recommendation_response.json
git commit -m "feat: type settings artifact metadata"
```

---

### Task 6: Add the Explicit Starting-Point and Instrumental-Only Experience

**Files:**
- Modify: `frontend/lib/features/sound_settings/presentation/pages/settings_setup_screen.dart`
- Modify: `frontend/lib/features/assessments/presentation/pages/audio_test_screen.dart:36-64`
- Modify: `frontend/lib/features/assessments/data/audio_staging_service.dart:41-51,86-100,155-175`
- Modify: `backend/karaok/application.py:2048-2070,2214-2230`
- Modify: `frontend/test/sound_settings/settings_setup_screen_test.dart`
- Create: `frontend/test/audio_staging_service_test.dart`
- Modify: `backend/tests/test_audio_validation.py`

**Interfaces:**
- Consumes: Task 5 `ControlPriors.toScale(AmplifierScale scale)` and typed metadata.
- Produces: optional `Use researched starting point` action and local physical-confirmation gate.
- Preserves: unchanged `SettingsSuggestionInput` wire payload; acknowledgement is UI workflow state, not a server claim.

- [ ] **Step 1: Add failing setup interaction tests**

Cover all three scale behaviors:

```dart
String knobText(WidgetTester tester, String name) {
  final field = tester.widget<TextFormField>(
    find.byKey(Key('knob-$name')),
  );
  return field.controller!.text;
}

await tester.tap(find.byKey(const Key('use-researched-starting-point')));
await tester.pump();
expect(knobText(tester, 'volume'), '4');
expect(knobText(tester, 'bass'), '5');
expect(knobText(tester, 'treble'), '5');
expect(knobText(tester, 'sharpness'), '5');
expect(knobText(tester, 'flatness'), '5');
expect(
  find.byKey(const Key('starting-point-acknowledgement')),
  findsOneWidget,
);
```

Repeat with `0-100` expecting `40/50/50/50/50`, and a custom `2-12` scale with step `0.5` expecting `6/7/7/7/7`.

Add tests proving:

- a saved profile's `lastPositions` appear on load without automatic prior replacement;
- tapping Continue before acknowledgement stays on the screen and shows `Confirm that the five physical controls match these positions.`;
- checking acknowledgement permits the existing guest/authenticated continuation;
- changing a knob or scale after acknowledgement clears acknowledgement;
- manually entered positions do not require this special acknowledgement;
- the rendered copy contains `karaoke instrumental playback` and contains neither `singer` nor `microphone direction`.

- [ ] **Step 2: Add failing MIDI rejection tests**

Add a Dart test around `stagePath` and a Flask upload-validation test. Both expect this message:

```text
MIDI event files are not rendered audio. Record the karaoke machine playback or select WAV, MP3, M4A, AAC, OGG, or FLAC.
```

Test both `.mid` and `.midi`; retain the existing generic unsupported-format behavior for unrelated extensions.

Use a real non-empty temporary file so extension validation is the observed failure:

```dart
test('symbolic MIDI files explain that rendered audio is required', () async {
  final directory = await Directory.systemTemp.createTemp('karaok-midi-test-');
  addTearDown(() => directory.delete(recursive: true));
  for (final extension in ['mid', 'midi']) {
    final file = File('${directory.path}/sample.$extension');
    await file.writeAsBytes([0x4d, 0x54, 0x68, 0x64]);
    await expectLater(
      AudioStagingService().stagePath(
        file.path,
        AudioSourceType.selectedFile,
        temporary: false,
      ),
      throwsA(
        isA<AudioStagingException>().having(
          (error) => error.message,
          'message',
          midiRenderedAudioMessage,
        ),
      ),
    );
  }
});
```

In the Flask test, post `io.BytesIO(b"MThd")` as both `sample.mid` and `sample.midi` to `/api/guest/audio-analysis` and, with the existing user authorization header, `/api/audio-uploads`. Assert status `400` plus the same error string. Import `io` in that test module.

- [ ] **Step 3: Run focused tests and verify the workflow is absent**

Run:

```powershell
Set-Location frontend
flutter test test/sound_settings/settings_setup_screen_test.dart test/audio_staging_service_test.dart --reporter expanded
Set-Location ../backend
py -m unittest tests.test_audio_validation -v
```

Expected: FAIL because the action, acknowledgement, and MIDI-specific explanation are absent.

- [ ] **Step 4: Implement the explicit prior state machine**

Add state fields:

```dart
SettingsProfileMetadata? _metadata;
bool _usingResearchedStartingPoint = false;
bool _startingPointAcknowledged = false;
```

The action must populate through the selected scale and reset confirmation:

```dart
void _applyResearchedStartingPoint() {
  final scale = _effectiveScaleOrNull();
  final metadata = _metadata;
  if (scale == null || metadata == null) return;
  final positions = metadata.controlPriors.toScale(scale).toJson();
  setState(() {
    for (final entry in positions.entries) {
      _positionControllers[entry.key]!.text = _formatNumber(entry.value);
    }
    _usingResearchedStartingPoint = true;
    _startingPointAcknowledged = false;
    _positionError = null;
  });
}
```

Render an outlined button with key `use-researched-starting-point`. Once used, render a `CheckboxListTile` with key `starting-point-acknowledgement` and label `I set all five physical controls to these positions.` In `_continue()`, enforce the confirmation only when `_usingResearchedStartingPoint` is true.

Any manual knob edit, profile selection, or scale change must set both flags to false. `_useProfile()` must load saved positions normally and never call `_applyResearchedStartingPoint()`.

- [ ] **Step 5: Replace scope-confusing copy**

Use these four controlled-comparison instructions:

```dart
const _GuidanceItem(text: 'Play the same karaoke instrumental song section for both recordings.'),
const _GuidanceItem(text: 'Play only the instrumental or MIDI accompaniment.'),
const _GuidanceItem(text: 'Keep the phone in the same position relative to the speakers.'),
const _GuidanceItem(text: 'Keep the room and playback source unchanged.'),
```

Change the settings-suggestion description in `AudioAnalysisPurposeDetails` to:

```dart
'Record the karaoke machine\'s rendered instrumental playback or select a rendered audio file to generate five amplifier settings.'
```

No copy in this flow may imply that singer distance or microphone processing is evaluated.

- [ ] **Step 6: Add matching symbolic-MIDI rejection on client and server**

Factor the exact message into a Dart constant and a Python constant. Before the generic extension rejection, check `mid` and `midi`. Apply the Python check to both guest and authenticated upload entry points so behavior cannot differ by account type.

- [ ] **Step 7: Run and format all affected UI/validation tests**

Run:

```powershell
Set-Location frontend
dart format lib/features/sound_settings/presentation/pages/settings_setup_screen.dart lib/features/assessments/presentation/pages/audio_test_screen.dart lib/features/assessments/data/audio_staging_service.dart test/sound_settings/settings_setup_screen_test.dart test/audio_staging_service_test.dart
flutter test test/sound_settings test/audio_staging_service_test.dart --reporter compact
Set-Location ../backend
py -m unittest tests.test_audio_validation -v
```

Expected: PASS for prior conversion, saved-position precedence, acknowledgement gating, instrumental-only copy, and both MIDI extensions.

- [ ] **Step 8: Commit the user workflow**

```powershell
git add frontend/lib/features/sound_settings/presentation/pages/settings_setup_screen.dart frontend/lib/features/assessments/presentation/pages/audio_test_screen.dart frontend/lib/features/assessments/data/audio_staging_service.dart frontend/test/sound_settings/settings_setup_screen_test.dart frontend/test/audio_staging_service_test.dart backend/karaok/application.py backend/tests/test_audio_validation.py
git commit -m "feat: guide instrumental amplifier setup"
```

---

### Task 7: Prove the Full Flow and Document Its Limits

**Files:**
- Modify: `frontend/integration_test/settings_generation_flow_test.dart`
- Modify: `tools/run-affected-tests.ps1`
- Modify: `tools/tests/affected-test-runner.tests.ps1`
- Modify: `README.md:30-50`
- Modify: `CHANGELOG.md`
- Modify: `docs/settings-profile-sources.md`

**Interfaces:**
- Consumes: Tasks 1-6 complete metadata, provenance, UI, schema, and recommendation flow.
- Produces: one repeatable affected-suite command and one authenticated Android/MySQL proof.

- [ ] **Step 1: Extend the integration test before changing its implementation path**

Update the Android test to:

1. Assert metadata includes both 64-character profile checksums and `control_priors`.
2. Select the `0-10` amplifier scale.
3. Tap `use-researched-starting-point` and assert positions `4/5/5/5/5`.
4. Assert Continue is blocked before physical acknowledgement.
5. Check `starting-point-acknowledgement`, record/select rendered audio, and generate all five settings.
6. Assert the returned recommendation contains the metadata genre version/checksum.
7. Apply it, reload the saved amplifier, and assert last positions equal the recommendation.
8. Submit the verification recording and assert every normalized delta is at most `7.5`.

Keep the existing cleanup in `finally` so the isolated test user/profile/assessment data does not leak between runs.

- [ ] **Step 2: Update the affected-test routing tests**

Add `tests.test_control_priors`, `tests.test_good_audio_thresholds`, `tests.test_audio_validation`, `tests.test_admin_data_api`, and `tests.test_security` to the `backend-settings` command. Add a routing assertion that changes to `backend/audio_thresholds/amplifier_control_priors.json` and `frontend/lib/features/sound_settings/domain/settings_profile_metadata.dart` select backend settings, Flutter settings, and Flutter analysis.

- [ ] **Step 3: Update user and engineering documentation**

Document this exact product statement in `README.md`:

```text
KaraOK records or accepts rendered karaoke instrumental playback, measures five audio features, and recommends bounded positions for Volume, Bass, Treble, Sharpness, and Flatness. It does not analyze a singer, vocal track, feedback, or microphone effects, and it does not parse symbolic .mid files.
```

Document the optional researched starting point, the required physical confirmation, the current low-confidence five-recording/unverified FMA limitation, and artifact provenance fields. Add a dated CHANGELOG entry covering the three retired tables and the fact that there are no replacement tables.

- [ ] **Step 4: Run the affected suites**

Run from the repository root:

```powershell
.\tools\run-affected-tests.ps1
```

Expected: PASS for backend settings, Flutter settings, Flutter analysis, and PowerShell tools selected from the changed paths.

- [ ] **Step 5: Run the historical full baseline**

Run:

```powershell
.\tools\run-affected-tests.ps1 -All
```

Expected: PASS for the complete backend suite, complete Flutter suite, Flutter analysis, and PowerShell tool tests.

- [ ] **Step 6: Run the authenticated Android/MySQL integration path**

With the phone connected and authorized, select the first Android device without hard-coding a device ID:

```powershell
$androidDevice = (flutter devices --machine | ConvertFrom-Json | Where-Object { $_.targetPlatform -like 'android-*' } | Select-Object -First 1).id
if (-not $androidDevice) { throw 'No authorized Android device is connected.' }
.\tools\run-affected-tests.ps1 -Integration -DeviceId $androidDevice
```

Expected: PASS. The runner creates/rebuilds only its explicitly named disposable integration database, starts Flask, executes the authenticated Flutter flow on the phone, and cleans its test state.

- [ ] **Step 7: Inspect the final diff for scope and secrets**

Run:

```powershell
git diff --check
git diff --name-only
rg -n -i "password\s*=|QRRQHZKRZLOOEH|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY" backend frontend database docs tools
```

Expected: `git diff --check` prints nothing; changed files match this plan; the secret scan finds no committed credential or private key. Legitimate password-policy source references may appear, but no real password value may appear.

- [ ] **Step 8: Commit integration proof and documentation**

```powershell
git add frontend/integration_test/settings_generation_flow_test.dart tools/run-affected-tests.ps1 tools/tests/affected-test-runner.tests.ps1 README.md CHANGELOG.md docs/settings-profile-sources.md
git commit -m "test: verify instrumental settings calibration flow"
```

---

## Completion Criteria

- All three artifacts validate their schema, exact keys, finite values, source evidence, version, and canonical checksum.
- Metadata exposes enabled genres and all three artifact provenances, plus the optional five-control starting point.
- The user can enter real current positions or explicitly apply and physically confirm researched starting positions on `0-10`, `0-100`, or custom scales.
- Every valid recommendation returns all five controls with the existing `15`/`7.5` normalized caps and Volume safety guard.
- Current unverified five-recording genre profiles cannot produce misleading high confidence.
- Authenticated quality and recommendation rows store exact artifact versions/checksums; guest results remain device-local.
- The authoritative schema has exactly the eleven retained tables and no retired IDs, foreign keys, policies, or lookup queries.
- Settings instructions refer only to rendered karaoke instrumental playback; symbolic MIDI input receives a clear rejection.
- Focused, full, static-analysis, PowerShell, schema, and Android/MySQL integration checks all pass.
