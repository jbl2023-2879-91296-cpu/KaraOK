# Adjusted Settings Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Sound Settings Recommendation module that converts a genre-labelled recording and five current amplifier-knob positions into safe, explainable adjusted targets, with one optional verification pass.

**Architecture:** A versioned genre-profile artifact feeds a pure Python recommendation engine. Existing guest and authenticated upload routes invoke the engine after audio analysis; authenticated results are committed with the assessment, while guest results remain device-local. Flutter adds a setup wizard, passes structured suggestion context through the existing audio workflow, and renders/apply-confirms the five targets.

**Tech Stack:** Python 3.13, Flask, MySQL 8, Python `unittest`, Flutter/Dart 3.12.2+, `flutter_test`, existing Librosa analyzer and HTTP/storage services.

**Spec:** `docs/superpowers/specs/2026-09-02-settings-generation-design.md`

## Global Constraints

- Generate Volume, Bass, Treble, Sharpness, and Flatness together; never return a silently partial recommendation.
- Require all five current positions and normalize every physical scale to internal 0-100 values.
- Provide 0-10 and 0-100 presets plus a custom minimum, maximum, and positive increment.
- Limit first-pass movement to 15 percent of full scale and verification movement to 7.5 percent.
- Never increase Volume when clipping or excessive distortion is detected.
- Use explicit genre selection; initial taxonomy is Rock, Pop, Ballad, Hip-Hop, Classical, R&B, and General/Other.
- Enable a genre only after a compatible, licensed source cohort satisfies the minimum sample rule.
- Persist authenticated recommendations; keep guest recommendations and guest amplifier settings device-local.
- Permit at most one verification refinement in v1.
- Guard every new route and settings-purpose upload with `SETTINGS_RECOMMENDATIONS_ENABLED=false`; return 404 while disabled without affecting quality evaluation.
- Use `GET /api/settings-profile-metadata` as Flutter's only source of enabled genre keys.
- Give guest initial recommendations a 24-hour signed verification token; never persist or log that token.
- Preserve the current Audio Quality Evaluation behavior and response shape.
- Do not bundle restricted source audio or genre annotations.
- Use versioned database migrations; do not require a destructive schema rebuild.
- Use TDD for every implementation task and commit only the files listed by that task.

---

## File Structure Map

### Backend profile and engine

- Create `backend/audio_thresholds/genre_profiles.py`: immutable profile types, JSON validation, genre normalization, and cached loading.
- Create `backend/audio_thresholds/derive_genre_profiles.py`: licensed manifest ingestion, exact KaraOK feature extraction, percentile derivation, manifest/report generation, and deterministic artifact writing.
- Create `backend/audio_thresholds/genre_audio_profiles.json`: generated runtime profile artifact.
- Create `backend/settings_recommendations/__init__.py`: public recommendation interfaces.
- Create `backend/settings_recommendations/models.py`: scale, knob, safety, request, adjustment, and result value objects.
- Create `backend/settings_recommendations/engine.py`: pure bounded recommendation calculation.
- Create `backend/tests/test_genre_profiles.py`: artifact and loader tests.
- Create `backend/tests/test_genre_profile_derivation.py`: deterministic derivation tests.
- Create `backend/tests/test_settings_recommendation_engine.py`: recommendation and safety tests.
- Create `backend/tests/fixtures/genre_measurements.csv`: small licensed/synthetic derivation fixture containing exact analyzer measurements.
- Create `backend/tests/fixtures/genre_audio_profiles.valid.json`: valid loader/engine fixture.

### Backend persistence and HTTP

- Create `database/migrations/20260902_01_settings_recommendations.sql`: additive production migration.
- Modify `database/schema.sql`: authoritative fresh-install tables and indexes.
- Create `backend/karaok/modules/settings_recommendations/__init__.py`: feature package marker.
- Create `backend/karaok/modules/settings_recommendations/service.py`: multipart validation, amplifier CRUD, ownership checks, recommendation serialization, and persistence statements.
- Create `backend/karaok/modules/settings_recommendations/routes.py`: amplifier and recommendation routes.
- Modify `backend/karaok/application.py`: register routes, generate recommendations in upload flows, and include them in history/detail responses.
- Modify `backend/karaok/config.py`: safe-default feature flag.
- Modify `backend/.env.example` and `deploy/ovh/backend.env.example`: published feature-flag defaults.
- Modify `backend/karaok/modules/admin_data/policy.py`: legacy settings read-only; new recommendation tables read-only.
- Modify `backend/tests/test_audio_pipeline.py`: authenticated/guest generation and atomic persistence tests.
- Create `backend/tests/test_settings_recommendation_api.py`: profile CRUD, ownership, apply, and verification contract tests.
- Modify `backend/tests/test_security.py`: fresh-schema and migration assertions.
- Modify `backend/tests/test_admin_data_api.py`: Data Administration capability assertions.

### Flutter data and UI

- Create `frontend/lib/features/sound_settings/domain/amplifier_profile.dart`: `AmplifierScale`, `KnobSettings`, and `AmplifierProfile`.
- Create `frontend/lib/features/sound_settings/domain/settings_recommendation.dart`: suggestion input/result models and response parsing.
- Replace `frontend/lib/features/sound_settings/data/settings_api.dart`: amplifier/recommendation API rather than legacy genre-setting CRUD.
- Create `frontend/lib/features/sound_settings/data/guest_amplifier_store.dart`: device-local guest amplifier profile.
- Create `frontend/lib/features/sound_settings/presentation/pages/settings_setup_screen.dart`: genre, scale, and current-position form.
- Replace `frontend/lib/features/assessments/presentation/pages/audio_settings_suggestion_screen.dart`: feature orchestrator that begins with setup.
- Modify `frontend/lib/features/assessments/presentation/pages/audio_test_screen.dart`: accept suggestion context and navigate to recommendation results.
- Modify `frontend/lib/features/assessments/data/assessment_api.dart`: typed suggestion upload parameters.
- Modify `frontend/lib/core/network/api_service.dart`: multipart fields and amplifier/recommendation endpoints.
- Create `frontend/lib/features/sound_settings/presentation/pages/settings_recommendation_screen.dart`: five result cards, apply confirmation, optional verification, comparison, and rollback.
- Modify `frontend/lib/features/reports/presentation/pages/previous_results_screen.dart`: reopen the correct result screen based on `analysis_purpose`.
- Delete `frontend/lib/features/sound_settings/presentation/pages/genre_select_screen.dart`: disconnected legacy flow.
- Delete `frontend/lib/features/sound_settings/presentation/pages/recommended_settings_screen.dart`: disconnected legacy flow.
- Add focused tests under `frontend/test/sound_settings/` and update `frontend/test/widget_test.dart`.

### Documentation and validation

- Create `backend/scripts/validate_settings_trials.py`: controlled before/after field-trial report.
- Create `docs/settings-profile-sources.md`: source licenses, versions, mappings, sample counts, and generation commands.
- Modify `README.md`, `backend/README.md`, and `CHANGELOG.md`: feature behavior and verification commands.
- Create `tools/run-settings-integration.ps1`: isolated MySQL/backend/Flutter integration harness.
- Create `frontend/integration_test/settings_generation_flow_test.dart`: real setup-to-persisted-result flow against Flask.
- Modify `frontend/pubspec.yaml` and `frontend/pubspec.lock`: add and lock the Flutter SDK `integration_test` development dependency.

---

### Task 1: Define and Validate the Genre Profile Contract

**Files:**
- Create: `backend/audio_thresholds/genre_profiles.py`
- Create: `backend/tests/test_genre_profiles.py`
- Create: `backend/tests/fixtures/genre_audio_profiles.valid.json`
- Modify: `backend/audio_thresholds/__init__.py`

**Interfaces:**
- Produces: `normalize_genre(value: str) -> str`
- Produces: `load_genre_profiles(path: str | Path = DEFAULT_GENRE_PROFILE_PATH) -> GenreProfileArtifact`
- Produces: `GenreProfileArtifact.profile_for(genre: str) -> GenreProfile`
- Produces: immutable `MetricTarget(lower, preferred, upper, robust_scale, unit)` and `GenreProfile(key, sample_count, metrics)`.

- [ ] **Step 1: Write failing loader and normalization tests**

```python
class GenreProfileTests(unittest.TestCase):
    def test_normalizes_supported_labels(self):
        self.assertEqual(normalize_genre("HipHop"), "hip-hop")
        self.assertEqual(normalize_genre("Classic"), "classical")
        self.assertEqual(normalize_genre("Soul-RnB"), "r&b")

    def test_loads_complete_five_metric_profile(self):
        artifact = load_genre_profiles(FIXTURES / "genre_audio_profiles.valid.json")
        rock = artifact.profile_for("Rock")
        self.assertEqual(set(rock.metrics), {"loudness", "bass", "treble", "sharpness", "flatness"})
        self.assertLess(rock.metrics["bass"].lower, rock.metrics["bass"].preferred)

    def test_rejects_degenerate_metric_range(self):
        payload = valid_payload()
        payload["genres"]["rock"]["metrics"]["bass"]["upper"] = payload["genres"]["rock"]["metrics"]["bass"]["preferred"]
        with self.assertRaisesRegex(ValueError, "lower < preferred < upper"):
            parse_genre_profile_artifact(payload)
```

- [ ] **Step 2: Run the focused test and confirm the missing-module failure**

Run: `cd backend; py -3.13 -m unittest tests.test_genre_profiles -v`
Expected: FAIL because `audio_thresholds.genre_profiles` does not exist.

- [ ] **Step 3: Implement immutable types and strict parsing**

```python
SUPPORTED_METRICS = ("loudness", "bass", "treble", "sharpness", "flatness")
GENRE_ALIASES = {
    "rock": "rock", "pop": "pop", "ballad": "ballad",
    "hiphop": "hip-hop", "hip-hop": "hip-hop", "hip hop": "hip-hop",
    "classic": "classical", "classical": "classical",
    "r&b": "r&b", "rnb": "r&b", "soul-rnb": "r&b",
    "general": "general", "other": "general", "general/other": "general",
}

@dataclass(frozen=True)
class MetricTarget:
    lower: float
    preferred: float
    upper: float
    robust_scale: float
    unit: str

def _metric_target(data: Mapping[str, Any]) -> MetricTarget:
    target = MetricTarget(
        lower=float(data["lower"]), preferred=float(data["preferred"]),
        upper=float(data["upper"]), robust_scale=float(data["robust_scale"]),
        unit=str(data["unit"]),
    )
    values = (target.lower, target.preferred, target.upper, target.robust_scale)
    if not all(math.isfinite(value) for value in values):
        raise ValueError("Genre metric values must be finite")
    if not target.lower < target.preferred < target.upper:
        raise ValueError("Genre metric values must satisfy lower < preferred < upper")
    if target.robust_scale <= 0:
        raise ValueError("Genre metric robust_scale must be positive")
    return target
```

- [ ] **Step 4: Add artifact checksum, schema-version, source metadata, metric completeness, and minimum-sample validation**

Compute the checksum from canonical JSON with `artifact_checksum` omitted and `sort_keys=True, separators=(",", ":")`. Reject schema versions other than `1`, duplicate normalized genres, missing source license/citation fields, and `sample_count < 5`.

- [ ] **Step 5: Run loader tests**

Run: `cd backend; py -3.13 -m unittest tests.test_genre_profiles -v`
Expected: all tests PASS.

- [ ] **Step 6: Export the public contract and commit**

```python
from .genre_profiles import GenreProfileArtifact, load_genre_profiles, normalize_genre
```

Run: `git add backend/audio_thresholds backend/tests/test_genre_profiles.py backend/tests/fixtures/genre_audio_profiles.valid.json && git commit -m "feat: define genre audio profile contract"`

---

### Task 2: Build the Reproducible Genre Profile Derivation Pipeline

**Files:**
- Create: `backend/audio_thresholds/derive_genre_profiles.py`
- Create: `backend/tests/test_genre_profile_derivation.py`
- Create: `backend/tests/fixtures/genre_measurements.csv`
- Create: `backend/audio_thresholds/genre_audio_profiles.json`
- Create: `docs/settings-profile-sources.md`

**Interfaces:**
- Consumes: `audio_engine.analyze_audio(path) -> dict[str, Any]`
- Consumes: Task 1 artifact validation and canonical checksum rules.
- Produces: `extract_measurement(analysis: Mapping[str, Any]) -> dict[str, float]`
- Produces: `derive_artifact(rows: Iterable[MeasurementRow], *, minimum_samples: int = 5) -> dict[str, Any]`
- Produces CLI: `python -m audio_thresholds.derive_genre_profiles --manifest <csv> --output <json> --report <md>`.

- [ ] **Step 1: Add failing extraction, quantile, determinism, and insufficient-cohort tests**

```python
def test_derives_ordered_profile_from_exact_karaok_measurements(self):
    rows = load_measurements(FIXTURES / "genre_measurements.csv")
    artifact = derive_artifact(rows, minimum_samples=5)
    bass = artifact["genres"]["rock"]["metrics"]["bass"]
    self.assertLess(bass["lower"], bass["preferred"])
    self.assertLess(bass["preferred"], bass["upper"])
    self.assertGreater(bass["robust_scale"], 0)

def test_generation_is_deterministic_regardless_of_manifest_order(self):
    rows = load_measurements(FIXTURES / "genre_measurements.csv")
    self.assertEqual(derive_artifact(rows), derive_artifact(reversed(rows)))

def test_disables_cohort_below_minimum(self):
    rows = load_measurements(FIXTURES / "genre_measurements.csv")[:4]
    with self.assertRaisesRegex(ValueError, "at least 5 compatible recordings"):
        derive_artifact(rows)
```

- [ ] **Step 2: Run the derivation tests and confirm failure**

Run: `cd backend; py -3.13 -m unittest tests.test_genre_profile_derivation -v`
Expected: FAIL because the derivation module does not exist.

- [ ] **Step 3: Implement manifest validation and exact analyzer extraction**

The manifest columns are exactly `path,genre,source,source_version,license,citation_url,recording_id`. Reject missing files, duplicate recording IDs, empty license/citation fields, unsupported genres, and non-finite analyzer values.

```python
FEATURE_PATHS = {
    "loudness": ("loudness", "integrated_lufs"),
    "bass": ("bass", "energy_percentage"),
    "treble": ("treble", "energy_percentage"),
    "sharpness": ("sharpness", "normalized_score"),
    "flatness": ("flatness", "mean"),
}

def extract_measurement(analysis: Mapping[str, Any]) -> dict[str, float]:
    extracted: dict[str, float] = {}
    for metric, path in FEATURE_PATHS.items():
        value: Any = analysis
        for key in path:
            value = value[key]
        number = float(value)
        if not math.isfinite(number):
            raise ValueError(f"{metric} measurement must be finite")
        extracted[metric] = number
    return extracted
```

- [ ] **Step 4: Implement robust profile statistics**

Sort rows by normalized genre and recording ID. Use NumPy percentiles `25`, `50`, and `75` for lower, preferred, and upper. Use `max(p75 - p25, abs(median) * 0.05, 1e-9)` as `robust_scale`. Reject a metric when its three target values are not strictly ordered; the report must identify the genre/metric and no artifact is written.

- [ ] **Step 5: Run derivation tests and validate the generated fixture artifact through Task 1**

Run: `cd backend; py -3.13 -m unittest tests.test_genre_profile_derivation tests.test_genre_profiles -v`
Expected: all tests PASS.

- [ ] **Step 6: Create the licensed source manifest outside Git and generate the real artifact**

Store source audio and the manifest under ignored `results/genre-profile-source/`. Use only recordings whose individual license permits feature derivation for the declared distribution model. Run:

```powershell
cd backend
py -3.13 -m audio_thresholds.derive_genre_profiles `
  --manifest ..\results\genre-profile-source\manifest.csv `
  --output audio_thresholds\genre_audio_profiles.json `
  --report ..\docs\settings-profile-sources.md `
  --minimum-samples 5
```

Expected: the report lists every enabled genre, exact compatible sample count, source/version/license, exclusions, metric quartiles, and artifact checksum. If any approved genre is absent, keep it disabled in Flutter until a compatible cohort is added; do not hand-author values.

- [ ] **Step 7: Re-run generation and prove deterministic output**

Run the command from Step 6 twice, then run `git diff --exit-code -- backend/audio_thresholds/genre_audio_profiles.json docs/settings-profile-sources.md`.
Expected: exit code `0` and no diff after the second generation.

- [ ] **Step 8: Commit generated profiles and attribution**

Run: `git add backend/audio_thresholds/derive_genre_profiles.py backend/audio_thresholds/genre_audio_profiles.json backend/tests/test_genre_profile_derivation.py backend/tests/fixtures/genre_measurements.csv docs/settings-profile-sources.md && git commit -m "feat: derive versioned genre audio profiles"`

---

### Task 3: Implement the Pure Bounded Recommendation Engine

**Files:**
- Create: `backend/settings_recommendations/__init__.py`
- Create: `backend/settings_recommendations/models.py`
- Create: `backend/settings_recommendations/engine.py`
- Create: `backend/tests/test_settings_recommendation_engine.py`

**Interfaces:**
- Consumes: `GenreProfile` from Task 1.
- Produces: `AmplifierScale`, `KnobSettings`, `SafetySignals`, `RecommendationRequest`, `KnobAdjustment`, and `SettingsRecommendation` dataclasses.
- Produces: `generate_recommendation(request: RecommendationRequest, profile: GenreProfile) -> SettingsRecommendation`.
- Produces: `SettingsRecommendation.to_dict() -> dict[str, Any]` for API persistence and JSON output.

- [ ] **Step 1: Write failing model, dead-zone, cap, clamp, and safety tests**

```python
def test_keeps_setting_when_measurement_is_in_genre_range(self):
    result = generate_recommendation(request(bass=50, bass_measurement=40), profile())
    self.assertEqual(result.adjustments["bass"].recommended, 50)
    self.assertEqual(result.adjustments["bass"].reason_code, "within_genre_range")

def test_caps_first_pass_at_fifteen_percent(self):
    result = generate_recommendation(request(bass=20, bass_measurement=0), profile())
    self.assertEqual(result.adjustments["bass"].recommended, 35)

def test_clipping_blocks_volume_increase(self):
    result = generate_recommendation(
        request(volume=40, loudness_measurement=-40, clipping=True), profile()
    )
    self.assertEqual(result.adjustments["volume"].recommended, 40)
    self.assertEqual(result.adjustments["volume"].reason_code, "volume_increase_blocked_by_clipping")

def test_verification_cap_is_seven_point_five_percent(self):
    result = generate_recommendation(request(bass=50, bass_measurement=0, verification=True), profile())
    self.assertLessEqual(abs(result.adjustments["bass"].delta_normalized), 7.5)
```

- [ ] **Step 2: Run the engine tests and confirm failure**

Run: `cd backend; py -3.13 -m unittest tests.test_settings_recommendation_engine -v`
Expected: FAIL because `settings_recommendations` does not exist.

- [ ] **Step 3: Implement scale and knob validation**

```python
@dataclass(frozen=True)
class AmplifierScale:
    minimum: float
    maximum: float
    step: float

    def normalize(self, value: float) -> float:
        self.validate(value)
        return 100.0 * (value - self.minimum) / (self.maximum - self.minimum)

    def denormalize(self, value: float) -> float:
        raw = self.minimum + min(100.0, max(0.0, value)) * (self.maximum - self.minimum) / 100.0
        steps = round((raw - self.minimum) / self.step)
        return min(self.maximum, max(self.minimum, self.minimum + steps * self.step))
```

Reject non-finite values, `minimum >= maximum`, `step <= 0`, and positions outside the scale.

- [ ] **Step 4: Implement per-metric adjustment with explicit knob mapping**

Use `volume -> loudness`, `bass -> bass`, `treble -> treble`, `sharpness -> sharpness`, and `flatness -> flatness`. Calculate signed distance to the nearest accepted boundary, divide by `robust_scale`, clamp error to `[-1, 1]`, multiply by a versioned sensitivity of `15.0`, and apply the initial/verification cap. Emit structured reason codes and do not embed presentation sentences in the engine.

- [ ] **Step 5: Implement all-or-unavailable behavior and confidence**

Return `unavailable` when any measurement is missing/non-finite, the recording is silent/corrupt/too short, or a required profile metric is absent. Assign `high`, `medium`, or `low` from recording validity, target distance, profile sample count, noise/distortion, and cross-coupling. Overall confidence is the lowest of the five settings.

- [ ] **Step 6: Run the engine and profile suites**

Run: `cd backend; py -3.13 -m unittest tests.test_settings_recommendation_engine tests.test_genre_profiles -v`
Expected: all tests PASS.

- [ ] **Step 7: Commit the pure engine**

Run: `git add backend/settings_recommendations backend/tests/test_settings_recommendation_engine.py && git commit -m "feat: generate bounded amplifier adjustments"`

---

### Task 4: Add Versioned Persistence Schema

**Files:**
- Create: `database/migrations/20260902_01_settings_recommendations.sql`
- Modify: `database/schema.sql`
- Modify: `backend/tests/test_security.py`

**Interfaces:**
- Produces tables `amplifier_profile` and `settings_recommendation` with owner-scoped indexes and cascade behavior.
- Produces one recommendation per assessment through `UNIQUE (assessment_id)`.

- [ ] **Step 1: Add failing schema assertions**

```python
def test_schema_persists_owned_amplifier_recommendations(self):
    schema = (ROOT / "database" / "schema.sql").read_text(encoding="utf-8")
    migration = (ROOT / "database" / "migrations" / "20260902_01_settings_recommendations.sql").read_text(encoding="utf-8")
    for sql in (schema, migration):
        self.assertIn("CREATE TABLE IF NOT EXISTS amplifier_profile", sql)
        self.assertIn("CREATE TABLE IF NOT EXISTS settings_recommendation", sql)
        self.assertIn("UNIQUE KEY uq_settings_recommendation_assessment", sql)
        self.assertIn("UNIQUE KEY uq_settings_recommendation_parent", sql)
        self.assertIn("parent_recommendation_id", sql)
        self.assertIn("ON DELETE CASCADE", sql)
```

- [ ] **Step 2: Run the schema test and confirm failure**

Run: `cd backend; py -3.13 -m unittest tests.test_security.SecurityValidationTests.test_schema_persists_owned_amplifier_recommendations -v`
Expected: FAIL because the migration and tables do not exist.

- [ ] **Step 3: Add the additive migration and matching fresh schema**

```sql
CREATE TABLE IF NOT EXISTS amplifier_profile (
    amplifier_profile_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    name VARCHAR(80) NOT NULL,
    scale_min DECIMAL(10,3) NOT NULL,
    scale_max DECIMAL(10,3) NOT NULL,
    scale_step DECIMAL(10,3) NOT NULL,
    last_positions JSON NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_amplifier_profile_user_name (user_id, name),
    KEY idx_amplifier_profile_user (user_id),
    CONSTRAINT fk_amplifier_profile_user FOREIGN KEY (user_id)
        REFERENCES user(user_id) ON DELETE CASCADE,
    CONSTRAINT chk_amplifier_profile_scale CHECK (scale_min < scale_max AND scale_step > 0)
);

CREATE TABLE IF NOT EXISTS settings_recommendation (
    recommendation_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    assessment_id INT NOT NULL,
    amplifier_profile_id BIGINT NOT NULL,
    parent_recommendation_id BIGINT NULL,
    genre VARCHAR(50) NOT NULL,
    current_positions JSON NOT NULL,
    recommended_positions JSON NOT NULL,
    adjustments JSON NOT NULL,
    original_score FLOAT NOT NULL,
    verification_score FLOAT NULL,
    overall_confidence VARCHAR(20) NOT NULL,
    algorithm_version VARCHAR(30) NOT NULL,
    genre_profile_version VARCHAR(30) NOT NULL,
    recommendation_status ENUM('generated','applied','verified','reverted','unavailable') NOT NULL DEFAULT 'generated',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    applied_at TIMESTAMP NULL,
    UNIQUE KEY uq_settings_recommendation_assessment (assessment_id),
    UNIQUE KEY uq_settings_recommendation_parent (parent_recommendation_id),
    KEY idx_settings_recommendation_user_created (user_id, created_at),
    CONSTRAINT fk_settings_recommendation_user FOREIGN KEY (user_id) REFERENCES user(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_settings_recommendation_assessment FOREIGN KEY (assessment_id) REFERENCES assessment(assessment_id) ON DELETE CASCADE,
    CONSTRAINT fk_settings_recommendation_amplifier FOREIGN KEY (amplifier_profile_id) REFERENCES amplifier_profile(amplifier_profile_id) ON DELETE CASCADE,
    CONSTRAINT fk_settings_recommendation_parent FOREIGN KEY (parent_recommendation_id) REFERENCES settings_recommendation(recommendation_id) ON DELETE SET NULL
);
```

Place tables after their referenced parent tables in `schema.sql`. In the migration, create `amplifier_profile` first and `settings_recommendation` second.

- [ ] **Step 4: Execute the migration against an empty disposable MySQL database and inspect relationships**

Run: `mysql -u root -p karaok_test < database/migrations/20260902_01_settings_recommendations.sql`
Then: `mysql -u root -p -D karaok_test -e "SHOW CREATE TABLE amplifier_profile; SHOW CREATE TABLE settings_recommendation;"`
Expected: both tables and all four recommendation foreign keys exist.

- [ ] **Step 5: Run schema tests and commit**

Run: `cd backend; py -3.13 -m unittest tests.test_security -v`
Expected: all tests PASS.

Run: `git add database backend/tests/test_security.py && git commit -m "feat: add settings recommendation schema"`

---

### Task 5: Implement Amplifier Profiles and Recommendation Ownership API

**Files:**
- Create: `backend/karaok/modules/settings_recommendations/__init__.py`
- Create: `backend/karaok/modules/settings_recommendations/service.py`
- Create: `backend/karaok/modules/settings_recommendations/routes.py`
- Create: `backend/tests/test_settings_recommendation_api.py`
- Modify: `backend/karaok/application.py:55-75,1550-1690,2354-2364`
- Modify: `backend/karaok/config.py`
- Modify: `backend/.env.example`
- Modify: `deploy/ovh/backend.env.example`

**Interfaces:**
- Produces service functions `get_profile_metadata()`, `list_amplifier_profiles(user_id)`, `create_amplifier_profile(user_id, payload)`, `update_amplifier_profile(user_id, profile_id, payload)`, `delete_amplifier_profile(user_id, profile_id)`, `get_owned_recommendation(user_id, recommendation_id)`, and `mark_recommendation_applied(user_id, recommendation_id)`.
- Produces `GET /api/settings-profile-metadata`, `GET/POST /api/amplifier-profiles`, `GET/PATCH/DELETE /api/amplifier-profiles/<id>`, `GET /api/settings-recommendations/<id>`, and `POST /api/settings-recommendations/<id>/apply`.
- Consumes existing `require_auth("user")`, `json_body()`, `bounded_number()`, `get_db()`, and `audit()` patterns.

- [ ] **Step 1: Write failing route and ownership tests**

```python
def test_profile_routes_require_user_auth(self):
    response = self.client.get("/api/amplifier-profiles")
    self.assertEqual(response.status_code, 401)

def test_profile_update_is_owner_scoped(self):
    connection = MagicMock()
    connection.cursor.return_value.rowcount = 0
    with patch.object(api, "get_db", return_value=connection), authenticated_user(7):
        response = self.client.patch("/api/amplifier-profiles/99", json={"name": "Stage Amp"})
    self.assertEqual(response.status_code, 404)
    self.assertIn(7, connection.cursor.return_value.execute.call_args.args[1])

def test_apply_updates_profile_positions_atomically(self):
    connection = MagicMock()
    cursor = connection.cursor.return_value
    cursor.fetchone.return_value = owned_recommendation_row()
    with patch.object(api, "get_db", return_value=connection), authenticated_user(7):
        response = self.client.post("/api/settings-recommendations/41/apply")
    self.assertEqual(response.status_code, 200)
    statements = "\n".join(call.args[0] for call in cursor.execute.call_args_list)
    self.assertIn("UPDATE amplifier_profile", statements)
    self.assertIn("recommendation_status = 'applied'", statements)
    connection.commit.assert_called_once()

def test_public_metadata_returns_only_enabled_genres_and_version(self):
    with patch.object(api, "SETTINGS_RECOMMENDATIONS_ENABLED", True):
        response = self.client.get("/api/settings-profile-metadata")
    self.assertEqual(response.status_code, 200)
    self.assertEqual(set(response.get_json()), {"profile_version", "enabled_genres"})

def test_settings_routes_are_hidden_while_feature_is_disabled(self):
    with patch.object(api, "SETTINGS_RECOMMENDATIONS_ENABLED", False):
        self.assertEqual(self.client.get("/api/settings-profile-metadata").status_code, 404)
        self.assertEqual(self.client.get("/api/amplifier-profiles").status_code, 404)
```

- [ ] **Step 2: Run the API tests and confirm missing-route failures**

Run: `cd backend; py -3.13 -m unittest tests.test_settings_recommendation_api -v`
Expected: FAIL with 404 responses for the new routes.

- [ ] **Step 3: Implement strict profile payload validation**

Accept only `name`, `scale_min`, `scale_max`, `scale_step`, and `last_positions`. Require names of 1-80 trimmed characters, finite scale values with `min < max`, positive step no larger than the range, and either null or exactly five in-range positions.

- [ ] **Step 4: Implement owner-scoped SQL and atomic apply behavior**

Every select/update/delete includes `user_id = %s`. Applying locks the recommendation and profile with `FOR UPDATE`, requires status `generated`, writes the recommended positions to `amplifier_profile.last_positions`, and changes status/applied time in one transaction.

- [ ] **Step 5: Add the safe-default feature flag and public metadata route**

Define `SETTINGS_RECOMMENDATIONS_ENABLED = os.getenv("SETTINGS_RECOMMENDATIONS_ENABLED", "false").lower() == "true"` in `config.py` and add `SETTINGS_RECOMMENDATIONS_ENABLED=false` to both published environment examples. Every new blueprint handler checks the flag before authentication and returns 404 when disabled. `GET /api/settings-profile-metadata` is unauthenticated and returns exactly `{"profile_version": artifact.profile_version, "enabled_genres": sorted(artifact.genres)}`; it exposes no source manifest or filesystem path.

- [ ] **Step 6: Register the blueprint**

Add `settings_recommendation_routes` to the imports and blueprint tuple in `application.py`. Keep endpoint functions thin: authenticate, parse IDs/body, call the service, audit, and jsonify.

- [ ] **Step 7: Run focused and security tests**

Run: `cd backend; py -3.13 -m unittest tests.test_settings_recommendation_api tests.test_security tests.test_modular_structure -v`
Expected: all tests PASS.

- [ ] **Step 8: Commit the profile API**

Run: `git add backend/karaok/modules/settings_recommendations backend/karaok/application.py backend/karaok/config.py backend/.env.example deploy/ovh/backend.env.example backend/tests/test_settings_recommendation_api.py && git commit -m "feat: manage owned amplifier profiles"`

---

### Task 6: Generate and Persist Recommendations in Audio Uploads

**Files:**
- Modify: `backend/karaok/modules/settings_recommendations/service.py`
- Modify: `backend/karaok/application.py:630-735,1696-1778,1879-2200`
- Modify: `backend/tests/test_audio_pipeline.py`
- Modify: `backend/tests/test_settings_recommendation_api.py`

**Interfaces:**
- Produces: `parse_suggestion_form(form, *, guest: bool, user_id: int | None) -> SuggestionContext | None`.
- Produces: `build_recommendation(summary, context, *, verification: bool) -> SettingsRecommendation`.
- Produces: `issue_guest_verification_token(recommendation: SettingsRecommendation, scale: AmplifierScale) -> str` and `parse_guest_verification_token(token: str) -> GuestVerificationContext` using HS256, the existing `JWT_SECRET`, audience `karaok-guest-settings-verification`, and a 24-hour expiry.
- Extends `persist_audio_analysis(assessment_id: int, upload_id: int, dump: dict[str, Any], *, recommendation: SettingsRecommendation | None = None, recommendation_context: SuggestionContext | None = None) -> dict[str, Any]` so analysis and recommendation commit together.
- Extends history/detail records with `settings_recommendation` when `analysis_purpose == "settings_suggestion"`.

- [ ] **Step 1: Add failing authenticated and guest upload-contract tests**

```python
def test_guest_settings_upload_returns_five_non_persisted_targets(self):
    response, status = post_guest_audio(
        analysis_purpose="settings_suggestion",
        genre="rock",
        amplifier_scale={"minimum": 0, "maximum": 10, "step": 0.5},
        current_settings={"volume": 5, "bass": 4, "treble": 6, "sharpness": 5, "flatness": 5},
    )
    payload = response.get_json()["settings_recommendation"]
    self.assertEqual(status, 201)
    self.assertIsNone(payload["id"])
    self.assertEqual(set(payload["recommended"]), {"volume", "bass", "treble", "sharpness", "flatness"})
    self.assertIsInstance(payload["verification_token"], str)

def test_quality_evaluation_does_not_require_settings_fields(self):
    response, status = post_guest_audio(analysis_purpose="quality_evaluation")
    self.assertEqual(status, 201)
    self.assertNotIn("settings_recommendation", response.get_json())

def test_analysis_and_recommendation_share_one_commit(self):
    connection = MagicMock()
    run_authenticated_settings_upload(connection)
    self.assertEqual(connection.commit.call_count, 2)
    # First commit creates the pending assessment/upload; second commits both result and recommendation.

def test_guest_verification_accepts_only_a_valid_initial_token(self):
    initial = post_guest_settings_audio().get_json()["settings_recommendation"]
    verified = post_guest_settings_audio(verification_token=initial["verification_token"])
    self.assertEqual(verified.status_code, 201)
    self.assertIsNone(verified.get_json()["settings_recommendation"]["verification_token"])

def test_expired_or_tampered_guest_verification_token_is_rejected(self):
    self.assertEqual(post_guest_settings_audio(verification_token=expired_token()).status_code, 400)
    self.assertEqual(post_guest_settings_audio(verification_token="tampered").status_code, 400)

def test_disabled_feature_rejects_only_settings_purpose_uploads(self):
    with patch.object(api, "SETTINGS_RECOMMENDATIONS_ENABLED", False):
        self.assertEqual(post_guest_audio(analysis_purpose="settings_suggestion")[1], 404)
        self.assertEqual(post_guest_audio(analysis_purpose="quality_evaluation")[1], 201)
```

- [ ] **Step 2: Run the focused pipeline tests and confirm failure**

Run: `cd backend; py -3.13 -m unittest tests.test_audio_pipeline tests.test_settings_recommendation_api -v`
Expected: FAIL because multipart suggestion fields are ignored and no recommendation is returned.

- [ ] **Step 3: Parse and validate multipart suggestion context before saving the upload**

For `settings_suggestion`, check the feature flag before accepting or saving the upload. Require normalized genre, JSON `current_settings`, and either an owned `amplifier_profile_id` or a complete guest `amplifier_scale`. Authenticated verification requires `verification_of`; reject it unless the parent belongs to the same user, is `applied`, and has no existing child. Guest verification requires `verification_token`; validate its signature, audience, expiry, initial-pass marker, genre, scale, recommended positions, before score, and versions. Require guest `current_settings` to equal the token's recommended positions after step rounding. Reject requests that mix `verification_of` and `verification_token`. For `quality_evaluation`, do not parse or validate suggestion-only fields; preserve backward compatibility.

- [ ] **Step 4: Generate recommendations from `summarize_audio_analysis()` output**

Map summary keys directly to engine measurements. Construct safety signals from analyzer output, including clipping and distortion. Load the selected `GenreProfile` and invoke `generate_recommendation`. For an initial guest pass, serialize with `id: null`, `persisted: false`, and a 24-hour signed verification token carrying only `kind`, `genre`, `scale`, `recommended_positions`, `before_score`, `profile_version`, `algorithm_version`, `initial_pass`, `aud`, `iat`, and `exp`. A guest verification response has `verification_token: null`, preventing a second refinement. Never persist or include the token in logs or audit payloads.

- [ ] **Step 5: Extend `persist_audio_analysis` to insert the recommendation before its existing commit**

Insert `settings_recommendation` after `audio_analysis_result` and before assessment/upload status updates. Reuse the same connection and rollback block. Return the serialized recommendation with the summary. Remove the legacy `genre_preset` lookup for new recommendations; keep nullable historical `preset_id` behavior unchanged for existing analysis rows during the migration window.

- [ ] **Step 6: Return and rebuild recommendations in create/history/detail responses**

Add a left join from assessment to settings recommendation in authenticated list/detail queries. Decode JSON fields with the existing `decoded_json` helper. Guest responses contain the transient object. Verification responses include `before_score`, `after_score`, `score_change`, and rollback/refinement status.

- [ ] **Step 7: Run backend feature and regression suites**

Run: `cd backend; py -3.13 -m unittest tests.test_audio_pipeline tests.test_settings_recommendation_api tests.test_security -v`
Expected: all tests PASS, including unchanged quality-evaluation tests.

- [ ] **Step 8: Commit upload integration**

Run: `git add backend/karaok/application.py backend/karaok/modules/settings_recommendations/service.py backend/tests/test_audio_pipeline.py backend/tests/test_settings_recommendation_api.py && git commit -m "feat: generate settings from audio uploads"`

---

### Task 7: Add Typed Flutter Models, API Calls, and Guest Amplifier Storage

**Files:**
- Create: `frontend/lib/features/sound_settings/domain/amplifier_profile.dart`
- Create: `frontend/lib/features/sound_settings/domain/settings_recommendation.dart`
- Replace: `frontend/lib/features/sound_settings/data/settings_api.dart`
- Create: `frontend/lib/features/sound_settings/data/guest_amplifier_store.dart`
- Modify: `frontend/lib/core/network/api_service.dart:387-482`
- Modify: `frontend/lib/features/assessments/data/assessment_api.dart`
- Create: `frontend/test/sound_settings/settings_models_test.dart`
- Create: `frontend/test/sound_settings/guest_amplifier_store_test.dart`

**Interfaces:**
- Produces Dart `AmplifierScale`, `KnobSettings`, `AmplifierProfile`, `SettingsSuggestionInput`, `KnobAdjustment`, and `SettingsRecommendation`.
- Produces `SettingsApi.getProfileMetadata/listProfiles/createProfile/updateProfile/deleteProfile/getRecommendation/applyRecommendation`.
- Extends `AssessmentApi.submitAudio({required String filePath, required String fileName, Uint8List? fileBytes, required int durationSeconds, String? genre, String analysisPurpose = 'quality_evaluation', bool guest = false, SettingsSuggestionInput? settingsSuggestion})`.

- [ ] **Step 1: Add failing normalization, JSON parsing, and local persistence tests**

```dart
test('0-10 settings normalize and round-trip at half steps', () {
  const scale = AmplifierScale(minimum: 0, maximum: 10, step: 0.5);
  expect(scale.normalize(5.5), 55);
  expect(scale.denormalize(57), 5.5);
});

test('recommendation requires all five adjustments', () {
  expect(
    () => SettingsRecommendation.fromJson(incompleteRecommendation),
    throwsFormatException,
  );
});

test('guest amplifier profile survives store recreation', () async {
  await GuestAmplifierStore(directoryProvider: provider).save(profile);
  final restored = await GuestAmplifierStore(directoryProvider: provider).read();
  expect(restored, profile);
});
```

- [ ] **Step 2: Run the focused Flutter tests and confirm failure**

Run: `cd frontend; flutter test test/sound_settings/settings_models_test.dart test/sound_settings/guest_amplifier_store_test.dart`
Expected: FAIL because the models and store do not exist.

- [ ] **Step 3: Implement immutable domain models with validation and JSON conversion**

Use `const` constructors where possible, equality/hashCode for storage tests, exactly five knob keys, finite-number checks, and scale range checks. `SettingsSuggestionInput.toMultipartFields()` returns JSON strings for `amplifier_scale` and `current_settings`, normalized genre, optional profile ID, optional integer `verificationOf`, and optional string `verificationToken`; the two verification fields are mutually exclusive. `SettingsRecommendation.fromJson` retains the nullable guest `verificationToken` returned by the backend.

- [ ] **Step 4: Replace legacy settings API methods and extend multipart upload**

Remove `getGenreSettings`, `getAllGenreSettings`, and `saveGenreSettings`. Add `getProfileMetadata`, the four amplifier profile routes, and recommendation get/apply routes. In `submitAudio`, add suggestion fields only when `analysisPurpose == 'settings_suggestion'`; throw `ArgumentError` when context is missing for that purpose.

- [ ] **Step 5: Implement device-local guest amplifier storage**

Store one JSON file at `<application-support>/karaok_guest/amplifier-profile.json` using a temporary file plus rename to avoid partial writes. Do not clear it during authentication token cleanup. Clear it only when guest reports are deliberately cleared or app storage is removed.

- [ ] **Step 6: Run model, store, cache, and session tests**

Run: `cd frontend; flutter test test/sound_settings test/analysis_cache_test.dart test/session_persistence_test.dart`
Expected: all tests PASS.

- [ ] **Step 7: Commit Flutter data contracts**

Run: `git add frontend/lib/features/sound_settings/domain frontend/lib/features/sound_settings/data frontend/lib/core/network/api_service.dart frontend/lib/features/assessments/data/assessment_api.dart frontend/test/sound_settings && git commit -m "feat: add settings recommendation client models"`

---

### Task 8: Build the Settings Setup Wizard

**Files:**
- Create: `frontend/lib/features/sound_settings/presentation/pages/settings_setup_screen.dart`
- Replace: `frontend/lib/features/assessments/presentation/pages/audio_settings_suggestion_screen.dart`
- Modify: `frontend/test/widget_test.dart`
- Create: `frontend/test/sound_settings/settings_setup_screen_test.dart`

**Interfaces:**
- Consumes Task 7 models/API/store.
- Produces `SettingsSetupScreen(onContinue: ValueChanged<SettingsSuggestionInput>)`.
- Produces `AudioSettingsSuggestionScreen(settingsApi, guestStore, audioScreenBuilder)` dependency-injection seams for widget and integration tests.

- [ ] **Step 1: Write failing setup and validation widget tests**

```dart
testWidgets('requires genre and all five current positions', (tester) async {
  await tester.pumpWidget(testApp(const AudioSettingsSuggestionScreen()));
  await tester.tap(find.text('Continue to Recording'));
  await tester.pump();
  expect(find.text('Select a genre.'), findsOneWidget);
  expect(find.text('Enter all five current knob positions.'), findsOneWidget);
});

testWidgets('builds normalized suggestion input', (tester) async {
  SettingsSuggestionInput? submitted;
  await tester.pumpWidget(testApp(SettingsSetupScreen(onContinue: (value) => submitted = value)));
  await fillScaleGenreAndFivePositions(tester);
  await tester.tap(find.text('Continue to Recording'));
  expect(submitted!.genre, 'rock');
  expect(submitted!.current.bass, 4);
});
```

- [ ] **Step 2: Run setup tests and confirm failure**

Run: `cd frontend; flutter test test/sound_settings/settings_setup_screen_test.dart test/widget_test.dart`
Expected: FAIL because the setup screen is absent and the old screen opens recording immediately.

- [ ] **Step 3: Implement amplifier and scale selection**

Authenticated users load server profiles and can create `My Amplifier`; guests load/save the local profile. Provide 0-10 and 0-100 presets plus custom minimum/maximum/step fields. Keep user-entered values when switching validation states; only rescale after an explicit confirmation when changing an existing scale.

- [ ] **Step 4: Implement enabled genre selection and five position controls**

Call `SettingsApi.getProfileMetadata()` when the screen loads and render only its `enabled_genres` values, using a local display-label map that does not decide availability. If the endpoint returns 404, show `Settings generation is not enabled` and disable Continue. Pair every slider with a numeric field, apply the physical increment, and validate all five values on submit.

- [ ] **Step 5: Add controlled-recording guidance and orchestrate navigation**

Display the same-song-section, same-room, same-phone-position, and same-playback-level guidance. On continue, push `AudioTestScreen(purpose: settingsSuggestion, settingsSuggestion: input)` through the injected builder.

- [ ] **Step 6: Run setup and existing navigation tests**

Run: `cd frontend; flutter test test/sound_settings/settings_setup_screen_test.dart test/widget_test.dart`
Expected: all tests PASS and Audio Quality Evaluation still opens its original recording screen directly.

- [ ] **Step 7: Commit the setup wizard**

Run: `git add frontend/lib/features/sound_settings/presentation/pages/settings_setup_screen.dart frontend/lib/features/assessments/presentation/pages/audio_settings_suggestion_screen.dart frontend/test && git commit -m "feat: collect amplifier settings before analysis"`

---

### Task 9: Render, Apply, and Optionally Verify Generated Settings

**Files:**
- Create: `frontend/lib/features/sound_settings/presentation/pages/settings_recommendation_screen.dart`
- Modify: `frontend/lib/features/assessments/presentation/pages/audio_test_screen.dart:65-550`
- Modify: `frontend/lib/features/reports/presentation/pages/previous_results_screen.dart:160-188`
- Create: `frontend/test/sound_settings/settings_recommendation_screen_test.dart`
- Create: `frontend/test/sound_settings/settings_verification_test.dart`

**Interfaces:**
- Consumes: `SettingsRecommendation` and `SettingsSuggestionInput` from Task 7.
- Produces `SettingsRecommendationScreen(recommendation, settingsApi, onVerify)`.
- Reuses `AudioTestScreen` with `verificationOf` and current positions set to the applied recommendation.

- [ ] **Step 1: Write failing five-card, apply, verification, and rollback tests**

```dart
testWidgets('renders all five current to recommended settings', (tester) async {
  await tester.pumpWidget(testApp(SettingsRecommendationScreen(recommendation: sample)));
  for (final label in ['Volume', 'Bass', 'Treble', 'Sharpness', 'Flatness']) {
    expect(find.text(label), findsOneWidget);
  }
  expect(find.text('4.0 → 5.5'), findsOneWidget);
});

testWidgets('verification remains optional', (tester) async {
  await tester.pumpWidget(testApp(SettingsRecommendationScreen(recommendation: sample)));
  expect(find.text("I've Applied These Settings"), findsOneWidget);
  expect(find.text('Record Again to Verify'), findsOneWidget);
  expect(find.text('Finish Without Verification'), findsOneWidget);
});

testWidgets('worse verification recommends rollback', (tester) async {
  await tester.pumpWidget(testApp(SettingsRecommendationScreen(recommendation: worseVerification)));
  expect(find.text('Return to your previous settings'), findsOneWidget);
});
```

- [ ] **Step 2: Run result tests and confirm failure**

Run: `cd frontend; flutter test test/sound_settings/settings_recommendation_screen_test.dart test/sound_settings/settings_verification_test.dart`
Expected: FAIL because the result screen does not exist.

- [ ] **Step 3: Navigate settings-purpose success to the new result screen**

In `AudioTestScreen._submit`, preserve existing `ResultsScreen` navigation for `qualityEvaluation`. For `settingsSuggestion`, parse the response recommendation and push `SettingsRecommendationScreen`. If the response marks recommendation unavailable, show the quality score plus the structured blocker and a record-again action.

- [ ] **Step 4: Implement result cards and structured explanations**

Render scale-aware current/recommended values, signed deltas, direction icons, confidence, and messages mapped from reason codes. Show analyzer safety warnings above the cards. Do not show an Apply button that implies remote control.

- [ ] **Step 5: Implement apply confirmation and one verification pass**

Authenticated Apply calls the server endpoint; guest Apply updates `GuestAmplifierStore`. `Record Again to Verify` is enabled only after apply. Authenticated verification starts `AudioTestScreen` with `verificationOf`; guest verification starts it with the response's `verificationToken`. Hide further verification actions when the returned recommendation has a parent or its guest verification token is null.

- [ ] **Step 6: Reopen settings recommendations from Records**

When `analysis_purpose == 'settings_suggestion'` and the record contains `settings_recommendation`, open `SettingsRecommendationScreen`; otherwise retain `ResultsScreen.fromRecord`. Guest records use the same discriminator from locally stored JSON.

- [ ] **Step 7: Run sound-settings and report regressions**

Run: `cd frontend; flutter test test/sound_settings test/widget_test.dart test/analysis_cache_test.dart`
Expected: all tests PASS.

- [ ] **Step 8: Commit the result and verification flow**

Run: `git add frontend/lib/features/assessments/presentation/pages/audio_test_screen.dart frontend/lib/features/sound_settings/presentation/pages/settings_recommendation_screen.dart frontend/lib/features/reports/presentation/pages/previous_results_screen.dart frontend/test && git commit -m "feat: show and verify generated amplifier settings"`

---

### Task 10: Retire the Conflicting Legacy Genre Settings Flow

**Files:**
- Delete: `frontend/lib/features/sound_settings/presentation/pages/genre_select_screen.dart`
- Delete: `frontend/lib/features/sound_settings/presentation/pages/recommended_settings_screen.dart`
- Delete: `backend/karaok/modules/genre_settings/routes.py`
- Delete: `backend/karaok/modules/genre_settings/__init__.py`
- Modify: `backend/karaok/application.py:65-70,1811-1855,2354-2364`
- Modify: `backend/karaok/modules/admin_data/policy.py`
- Modify: `backend/tests/test_modular_structure.py`
- Modify: `backend/tests/test_admin_data_api.py`

**Interfaces:**
- Removes public `/api/genre-settings` CRUD and unreachable Flutter screens.
- Keeps `genre_preset` and `user_genre_setting` readable for historical compatibility only.
- Adds read-only Admin policies for `amplifier_profile` and `settings_recommendation`.

- [ ] **Step 1: Write failing policy and removed-route tests**

```python
def test_legacy_genre_tables_are_read_only(self):
    for table in ("genre_preset", "user_genre_setting"):
        policy = table_policy(table)
        self.assertFalse(policy.creatable)
        self.assertFalse(policy.updatable)
        self.assertFalse(policy.deletable)

def test_new_settings_tables_are_read_only_in_admin_api(self):
    self.assertTrue(table_policy("amplifier_profile").readable)
    self.assertFalse(table_policy("settings_recommendation").updatable)

def test_legacy_genre_settings_route_is_removed(self):
    self.assertEqual(self.client.get("/api/genre-settings").status_code, 404)
```

- [ ] **Step 2: Run focused tests and confirm failure**

Run: `cd backend; py -3.13 -m unittest tests.test_admin_data_api tests.test_modular_structure -v`
Expected: FAIL because legacy tables remain writable and routes remain registered.

- [ ] **Step 3: Remove legacy routes/functions/screens and update imports**

Delete the four listed files, remove `genre_settings_routes` registration, remove `get_genre_settings` and `save_genre_settings`, and ensure `rg "GenreSelectScreen|RecommendedSettingsScreen|getGenreSettings|saveGenreSettings" frontend/lib backend/karaok` returns no matches.

- [ ] **Step 4: Make legacy and new Admin policies read-only**

Retain labels that explicitly say `Legacy genre presets` and `Legacy user genre settings`. Add new-table policies without create/update/delete fields. Do not expose recommendation JSON through any credential-sensitive table path.

- [ ] **Step 5: Run backend and Flutter regression suites**

Run: `cd backend; py -3.13 -m unittest tests.test_admin_data_api tests.test_modular_structure tests.test_security -v`
Run: `cd frontend; flutter test`
Expected: all tests PASS.

- [ ] **Step 6: Commit legacy retirement**

Run: `git add -A frontend/lib/features/sound_settings backend/karaok/modules/genre_settings backend/karaok/application.py backend/karaok/modules/admin_data/policy.py backend/tests && git commit -m "refactor: retire legacy genre settings flow"`

---

### Task 11: Add Controlled Trial Validation and Cross-Layer Contract Coverage

**Files:**
- Create: `backend/scripts/validate_settings_trials.py`
- Create: `backend/tests/test_settings_trial_validation.py`
- Create: `frontend/test/sound_settings/settings_contract_fixture_test.dart`
- Create: `frontend/test/fixtures/settings_recommendation_response.json`
- Modify: `backend/tests/test_settings_recommendation_api.py`

**Interfaces:**
- Produces CLI: `python backend/scripts/validate_settings_trials.py <csv> --output <json>`.
- Consumes CSV columns `trial_id,genre,start_profile,before_score,after_score,clipping_violation`.
- Produces JSON fields `trial_count,median_score_change,improved_count,worsened_count,unchanged_count,clipping_violation_count,passed`.
- Produces one shared API response fixture parsed by both backend expectations and Dart models.

- [ ] **Step 1: Write failing acceptance-report tests**

```python
def test_trial_report_requires_positive_median_majority_and_no_clipping(self):
    report = evaluate_trials([
        trial("a", 70, 80), trial("b", 72, 75), trial("c", 80, 79),
    ])
    self.assertEqual(report["improved_count"], 2)
    self.assertEqual(report["clipping_violation_count"], 0)
    self.assertTrue(report["passed"])

def test_any_clipping_violation_fails_release_gate(self):
    report = evaluate_trials([trial("a", 70, 80, clipping=True)])
    self.assertFalse(report["passed"])
```

- [ ] **Step 2: Run validation tests and confirm failure**

Run: `cd backend; py -3.13 -m unittest tests.test_settings_trial_validation -v`
Expected: FAIL because the validation script does not exist.

- [ ] **Step 3: Implement deterministic CSV validation and JSON reporting**

Reject duplicate trial IDs, unsupported genres, non-finite/out-of-range scores, and empty input. `passed` is true only when median change is positive, improved trials are strictly more than 50 percent, improved count exceeds worsened count, and clipping violations equal zero.

- [ ] **Step 4: Add a shared complete API fixture and parse it in Python and Dart tests**

The fixture contains all five current/recommended settings, all five adjustment objects, source/profile/algorithm versions, confidence, score, genre, scale, and verification metadata. Backend tests compare serialization to the fixture schema; Dart tests parse it and assert every field.

- [ ] **Step 5: Run cross-layer tests**

Run: `cd backend; py -3.13 -m unittest tests.test_settings_trial_validation tests.test_settings_recommendation_api -v`
Run: `cd frontend; flutter test test/sound_settings/settings_contract_fixture_test.dart`
Expected: all tests PASS.

- [ ] **Step 6: Commit validation tooling**

Run: `git add backend/scripts/validate_settings_trials.py backend/tests frontend/test/sound_settings/settings_contract_fixture_test.dart frontend/test/fixtures/settings_recommendation_response.json && git commit -m "test: validate settings recommendations across layers"`

---

### Task 12: Prove the Full Settings Flow Against Flask and MySQL

**Files:**
- Create: `tools/run-settings-integration.ps1`
- Create: `frontend/integration_test/settings_generation_flow_test.dart`
- Modify: `frontend/pubspec.yaml`
- Modify: `frontend/pubspec.lock`

**Interfaces:**
- Produces `tools/run-settings-integration.ps1`, an opt-in Windows harness fixed to database `karaok_settings_e2e` and backend port `5100`.
- Consumes a MySQL login path named `karaok-e2e` for database creation/removal and `KARAOK_E2E_DB_USER`/`KARAOK_E2E_DB_PASSWORD` for the restricted backend connection.
- Exercises Flutter setup input, authenticated profile creation, a real multipart WAV upload, Flask analysis/recommendation, MySQL persistence, history reload, and result rendering.

- [ ] **Step 1: Add the Flutter integration dependency and a failing real-flow test**

Add the SDK dependency:

```yaml
dev_dependencies:
  integration_test:
    sdk: flutter
```

The test uses `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`, registers a unique test user through `AuthApi` with development OTP exposure, creates an amplifier profile through `SettingsApi`, pumps `SettingsSetupScreen`, selects an enabled genre returned by `getProfileMetadata`, fills all five positions, and captures the resulting `SettingsSuggestionInput`. A test helper writes a deterministic four-second mono 44.1 kHz PCM WAV to `Directory.systemTemp` using `dart:io`; do not commit source audio.

- [ ] **Step 2: Submit through the real client and assert persistence plus rendering**

Call `AssessmentApi.submitAudio` with the captured input and `guest: false`. Assert the response has a non-null recommendation ID, `persisted == true`, and exactly five targets. Reload the assessment through `AssessmentApi.getAudioTest`, assert the same recommendation ID, then pump `SettingsRecommendationScreen` and verify the five labels and current-to-recommended values. Delete the temporary WAV in `addTearDown`.

- [ ] **Step 3: Run the test without a backend and confirm the expected connection failure**

Run: `cd frontend; flutter test integration_test/settings_generation_flow_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:5100/api`
Expected: FAIL at the first real API call because the isolated backend is not running.

- [ ] **Step 4: Implement the isolated PowerShell harness**

The script performs these exact operations inside `try/finally`:

1. Set `$settingsE2eDb = 'karaok_settings_e2e'` and abort unless it equals that literal and matches `^[a-z0-9_]+$`.
2. Require `mysql`, `backend\.venv\Scripts\python.exe`, Flutter Windows desktop support, `KARAOK_E2E_DB_USER`, and `KARAOK_E2E_DB_PASSWORD`.
3. Through `mysql --login-path=karaok-e2e`, drop only `karaok_settings_e2e` if it exists, create it, and import `database/schema.sql` plus the Task 4 migration.
4. Create a unique directory below `[System.IO.Path]::GetTempPath()` for uploads/results. Set the child backend environment to `DB_NAME=karaok_settings_e2e`, the two restricted credentials, `APP_PORT=5100`, `DEV_MODE=true`, `EXPOSE_REGISTRATION_OTP=true`, `SETTINGS_RECOMMENDATIONS_ENABLED=true`, an integration-only 64-character `JWT_SECRET`, and the unique audio directories.
5. Launch `backend\.venv\Scripts\python.exe backend\run.py` with `Start-Process -PassThru -WindowStyle Hidden`, poll `/api/health` for at most 30 seconds, then run the Flutter command from Step 3.
6. In `finally`, stop only the captured backend process, drop only the exact validated test database, resolve `$settingsE2eTemp` and verify that it remains beneath `[System.IO.Path]::GetTempPath()` before `Remove-Item -LiteralPath $settingsE2eTemp -Recurse -Force`, and restore every process environment value changed by the script.

The script exits non-zero when schema import, health polling, Flutter, database cleanup, or temp cleanup fails and never reads or modifies the developer database named `karaok_db`.

- [ ] **Step 5: Run the harness and inspect the persisted row during the test**

Run: `powershell -ExecutionPolicy Bypass -File tools/run-settings-integration.ps1`
Expected: the test passes, `GET /api/audio-tests/<id>` returns the same persisted recommendation rendered by Flutter, and final cleanup removes `karaok_settings_e2e` and the dedicated temporary directory.

- [ ] **Step 6: Commit the full-stack integration harness**

Run: `git add tools/run-settings-integration.ps1 frontend/integration_test/settings_generation_flow_test.dart frontend/pubspec.yaml frontend/pubspec.lock && git commit -m "test: cover settings generation end to end"`

---

### Task 13: Document, Verify, and Prepare Internal Rollout

**Files:**
- Modify: `README.md`
- Modify: `backend/README.md`
- Modify: `CHANGELOG.md`
- Modify: `deploy.md`
- Modify: `backend/tests/test_modular_structure.py`

**Interfaces:**
- Documents the module flow, source attribution, additive migration, feature flag, controlled trial format, and rollback behavior.

- [ ] **Step 1: Add documentation assertions to modular structure tests**

```python
def test_public_docs_name_settings_generation_safety_and_sources(self):
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    self.assertIn("Adjusted amplifier settings", readme)
    self.assertIn("Record Again to Verify", readme)
    self.assertIn("docs/settings-profile-sources.md", readme)
```

- [ ] **Step 2: Run the documentation test and confirm failure**

Run: `cd backend; py -3.13 -m unittest tests.test_modular_structure -v`
Expected: FAIL until documentation is updated.

- [ ] **Step 3: Document behavior, migration, feature flag, and operational checks**

Document the `SETTINGS_RECOMMENDATIONS_ENABLED=false` safe default implemented in Task 5, migration application, profile artifact checksum verification, source attribution, API health checks, audit events, and disabling the flag as rollback. State that KaraOK recommends physical positions but never controls the amplifier.

- [ ] **Step 4: Run formatters and static checks**

Run: `dart format frontend/lib frontend/test`
Run: `cd frontend; flutter analyze`
Run: `cd backend; py -3.13 -m compileall karaok audio_thresholds settings_recommendations`
Expected: formatting completes; analyzer and compileall exit `0`.

- [ ] **Step 5: Run full automated suites**

Run: `cd frontend; flutter test`
Run: `cd backend; py -3.13 -m unittest discover -s tests -p "test_*.py" -v`
Run: `cd admin; composer test`
Expected: all Flutter, backend, and Admin Console tests PASS.

- [ ] **Step 6: Apply the migration in staging and run controlled trials**

Apply `database/migrations/20260902_01_settings_recommendations.sql`, enable the feature flag in staging, and collect at least five songs per enabled genre across low, neutral, and high starts. Run:

```powershell
py -3.13 backend\scripts\validate_settings_trials.py `
  results\settings-trials.csv `
  --output results\settings-trials-report.json
```

Expected: report `passed` is `true`; otherwise leave the feature flag disabled and inspect every worsening/low-confidence trial.

- [ ] **Step 7: Commit documentation and rollout controls**

Run: `git add README.md backend/README.md CHANGELOG.md deploy.md backend/tests/test_modular_structure.py && git commit -m "docs: prepare settings generation rollout"`

- [ ] **Step 8: Request final code review before enabling production**

Use `superpowers:requesting-code-review` against the complete feature diff. Resolve all correctness, safety, ownership, migration, and test concerns; rerun Step 5 after the final change. Do not enable production until the automated suites and controlled-trial gate both pass.
