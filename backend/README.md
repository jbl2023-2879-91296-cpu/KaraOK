# KaraOK backend

The Flask backend owns authentication, audio analysis, persisted assessments,
amplifier profiles, and adjusted-settings recommendations. Run commands in this
document from `backend/` unless a command says otherwise.

## Package layout

`app.py` remains the development/WSGI compatibility entry point. The Flask
application is wired in `karaok/application.py`; feature implementations live
in the following packages:

| Package | Responsibility |
| --- | --- |
| `karaok/core/` | Configuration, database access, validation, shared account and recommendation values, scoring/profile loaders, audit writing, and safe artifact operations |
| `karaok/auth/` | Registration, login, tokens, password changes, email delivery, and authorization |
| `karaok/users/` | User profile updates |
| `karaok/audio_pipeline/` | Upload orchestration, analyzer subprocess execution, summaries, adjustment recommendations, and transient visualization handling |
| `karaok/results/` | Assessment/upload persistence, historical presentation, amplifier profiles, saved recommendations, and visualization retrieval |
| `karaok/admin/` | Administrative user/log queries, data operations, and reports |
| `karaok/system/` | Health checks |
| `karaok/modules/` | Existing Flask Blueprint names and route import paths |

Use `karaok.audio_pipeline.pipeline` as the processing interface outside the
pipeline package. Results never call back into the pipeline: record writers
receive prepared summaries, while history preserves stored scoring snapshots
and the existing legacy-null-score fallback through shared core scoring.
Recommendation writes retain ownership and verification checks under the
original database transaction and row locks.

The numerical audio engine remains in `audio_engine/`, launched through
`audio_analyzer.py` as a subprocess. The bounded recommendation engine remains
in `settings_recommendations/engine.py`. Threshold JSON files retain their
existing paths in `audio_thresholds/`; their shared loaders now live in core.

Historical imports remain supported. `karaok/legacy_exports.py` exposes the
former application helpers, and `karaok/compatibility.py` connects legacy
dependency overrides to the extracted implementations. New feature code should
import its owning modules directly, never `application.py` or `legacy_exports.py`.
`core/runtime.py` owns the shared Flask instance and extensions; application
composition registers request hooks, error handlers, and Blueprints.

## Settings generation module flow

1. `karaok/modules/settings_recommendations/routes.py` exposes feature-flagged,
   ownership-checked amplifier-profile and recommendation endpoints.
2. `karaok/audio_pipeline/recommendations.py` validates the selected
   genre, profile scale, all five current positions, and verification context.
3. `audio_engine` measures loudness, bass, treble, sharpness, and flatness from
   the uploaded recording.
4. `settings_recommendations/engine.py` converts the difference from the
   versioned genre targets into bounded, scale-aligned physical knob targets.
5. `karaok/results/records.py` saves the assessment, analysis, five-target
   recommendation, and optional verification relationship in one owned history.

KaraOK only recommends positions. It never connects to, controls, or moves an
amplifier. A user applies the positions manually and may record the same song
section again to verify the score change.

## Configuration and migration

Settings generation is fail-closed by default:

```dotenv
SETTINGS_RECOMMENDATIONS_ENABLED=false
```

For an existing database, back it up and apply the additive migration once:

```powershell
mysql --database=karaok_db -u root -p < ..\database\migrations\20260902_01_settings_recommendations.sql
```

The migration adds `amplifier_profile` and `settings_recommendation`; it does
not drop or rewrite existing tables. Keep the feature flag disabled until the
migration, automated tests, staging health checks, and controlled trials pass.
The fresh-install `database/schema.sql` already includes these tables.

## Genre profile integrity and sources

`audio_thresholds/genre_audio_profiles.json` is immutable runtime input. Loading
it verifies its canonical checksum and rejects altered content:

```powershell
.\.venv\Scripts\python.exe -c "from audio_thresholds import load_genre_profiles; print(load_genre_profiles().artifact_checksum)"
```

Expected checksum:

```text
125800de3f963adf02e20a8edb2a4a492f750ae7814a1ac3272ecfdf222e6ec2
```

The licensed recording manifest, selection rules, source attribution, disabled
genres, and quartiles are documented in `../docs/settings-profile-sources.md`.
Do not hand-edit the generated JSON or enable a genre without a compatible,
licensed cohort that passes the derivation tests.

## API and operational checks

The module provides:

- `GET /api/settings-profile-metadata`
- authenticated CRUD under `/api/amplifier-profiles`
- authenticated read/apply operations under `/api/settings-recommendations`
- authenticated `POST /api/audio-uploads` with
  `analysis_purpose=settings_suggestion`

After deployment, `/api/health` must return `{"db":"connected","status":"ok"}`.
Inspect audit logs for `amplifier_profile_created`,
`amplifier_profile_updated`, `amplifier_profile_deleted`,
`audio_upload_analyzed` with `purpose=settings_suggestion`, and
`settings_recommendation_applied`.

## Controlled-trial release gate

Collect at least five controlled songs for every enabled genre, covering low,
neutral, and high starting positions. The CSV columns must be exactly:

```text
trial_id,genre,start_profile,before_score,after_score,clipping_violation
```

Validate the evidence from the repository root:

```powershell
py -3.13 backend\scripts\validate_settings_trials.py `
  results\settings-trials.csv `
  --output results\settings-trials-report.json
```

Rollout requires `passed: true`, no clipping violations, a positive median
score change, and more improved than worsened trials. Inspect every worsening
or low-confidence result even when the aggregate gate passes.

## Rollback

Set `SETTINGS_RECOMMENDATIONS_ENABLED=false` and restart the API. The settings
routes then return `404` and new settings-purpose uploads are rejected, while
the additive tables and existing audit/history records remain intact. Do not
drop the tables as a rollback. Re-enable only after correcting the issue and
rerunning all automated and controlled-trial gates.

## Tests

```powershell
.\.venv\Scripts\python.exe -m compileall karaok audio_thresholds settings_recommendations
.\.venv\Scripts\python.exe -m unittest discover -s tests -p "test_*.py" -v
```

Use the interpreter from a working local virtual environment. The package
contract tests cover route/signature preservation, independent imports,
the pipeline import boundary, and legacy dependency-override restoration.
The suite does not replace live MySQL, SMTP, or deployed client smoke tests.

Backend database connections use UTC sessions so MySQL `TIMESTAMP` values
serialize correctly before clients convert them to local time. Workbench and
the MySQL server's global timezone do not need to change.

To include the timestamp round-trip integration test against the configured
local MySQL database, set `$env:KARAOK_TEST_MYSQL='1'` before running the suite.
It uses a temporary table and does not modify application records.
