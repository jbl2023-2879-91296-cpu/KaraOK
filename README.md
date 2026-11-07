<div align="center">

<img src="frontend/assets/branding/karaok-icon.png" alt="KaraOK logo" width="128" height="128">

<h1>KaraOK</h1>

<p><strong>Record. Assess. Compare.</strong></p>
<p>Understand your karaoke sound with five-feature quality assessments,<br>visual reports, and amplifier settings suggestions.</p>

<p>
  <a href="https://github.com/jbl2023-2879-91296-cpu/KaraOK/releases"><img src="https://img.shields.io/badge/version-1.11.0-4A90D9?style=flat-square" alt="Version 1.11.0"></a>
  <img src="https://img.shields.io/badge/platform-Android-3DDC84?style=flat-square&amp;logo=android&amp;logoColor=white" alt="Platform: Android">
  <img src="https://img.shields.io/badge/client-Flutter-02569B?style=flat-square&amp;logo=flutter&amp;logoColor=white" alt="Client: Flutter">
  <img src="https://img.shields.io/badge/API-Flask-182C39?style=flat-square&amp;logo=flask&amp;logoColor=white" alt="API: Flask">
  <img src="https://img.shields.io/badge/database-MySQL-4479A1?style=flat-square&amp;logo=mysql&amp;logoColor=white" alt="Database: MySQL">
</p>

<p>
  <a href="#quick-start">Quick start</a> &middot;
  <a href="build.md">Build Android</a> &middot;
  <a href="deploy.md">Deploy backend</a> &middot;
  <a href="CHANGELOG.md">Changelog</a>
</p>

<p><sub>Loudness &middot; Bass &middot; Treble &middot; Sharpness &middot; Flatness</sub></p>

</div>

---

KaraOK is an Android app for checking karaoke playback quality. The Flutter app
records or selects audio, a Flask API measures five sound features against
reference recordings, and the app shows a score, plain-language explanations,
noise and distortion estimates, and waveform and spectrogram reports. Signed-in
history is stored in MySQL; guests keep their reports on the device.

## Status

| Item | Value |
| --- | --- |
| Latest released APK | 1.11.0+17 (in `dist/`), app-wide layout and consistency pass |
| Production backend | Deployed 2026-11-07 from `main` (see [CHANGELOG](CHANGELOG.md)) |
| Production API | `https://139.99.89.112/api` |
| Default branch | `main` |

## Features

- **Guest first**: three free evaluations per device, no account needed.
  Email-only sign-up; profile details can be filled in later.
- **Audio quality evaluation**: record up to five minutes or pick a file. The
  result shows a 0 to 100 score, a grade (Acceptable, Needs Improvement,
  Problematic), each measurement with Good / Too high / Too low, noise and
  distortion estimates, and visual reports.
- **Adjusted amplifier settings**: describe the amplifier's knob scale and
  current positions, record, and get five bounded knob positions with reasons.
  After applying them, **Record Again to Verify** checks the result. KaraOK
  never controls the amplifier. Controlled by `SETTINGS_RECOMMENDATIONS_ENABLED`
  (off in production until the trial gate in [deploy.md](deploy.md) passes).
- **Records**: search, filters, sorting, and two-report comparison.
- **Glossary** of every sound term, available from Settings and reports.
- **Admin Console**: a local PHP console for analytics and policy-limited record
  management through the Data Administration API.

How scores are calculated is documented in the
[assessment profile](backend/audio_thresholds/README.md) and the
[empirical scoring report](docs/empirical-scoring-report.md). Settings
suggestions and their sources are covered in
[settings profile sources](docs/settings-profile-sources.md).

## Repository layout

```text
KaraOK/
|-- frontend/       Flutter app and its tests           -> frontend/README.md
|-- backend/        Flask API, audio engine, thresholds  -> backend/README.md
|-- database/       Fresh-install schema and migrations  -> database/README.md
|-- admin/          Local Admin Console (PHP)            -> admin/CONSOLE.md
|-- deploy/ovh/     Server service, Nginx and backup files
|-- tools/          Build, test and dev scripts          -> tools/README.md
|-- docs/           Calibration sources, audits and UAT evidence
|-- build.md        Android signing and builds
|-- deploy.md       Server release and recovery runbook
`-- CHANGELOG.md    Release history
```

Local-only folders (ignored by Git): `dist/` for built APKs, the audio sample
folders, `results/` and `sample/` for analysis output, `output/` for generated
documents, and `tmp/` for scratch files.

## Quick start

Prerequisites: Flutter (Dart `^3.12.2`), Python 3.13, MySQL 8, FFmpeg and
libsndfile.

1. **Database**: import the fresh-install schema into an empty MySQL server.

   ```powershell
   mysql -u root -p --execute="source database/schema.sql"
   ```

2. **API**

   ```powershell
   cd backend
   python -m venv .venv
   .\.venv\Scripts\python.exe -m pip install -r requirements.txt
   Copy-Item .env.example .env   # then fill in database, JWT, SMTP, CORS, storage
   .\.venv\Scripts\python.exe run.py
   ```

   Health check: `http://127.0.0.1:5000/api/health`.

3. **App**

   ```powershell
   cd frontend
   flutter pub get
   flutter run --dart-define=API_BASE_URL=http://127.0.0.1:5000/api
   ```

   Use `http://10.0.2.2:5000/api` from an Android emulator.

Or start everything at once with `./tools/run-dev.ps1`.

## Testing

From the repository root on Windows:

```powershell
./tools/run-affected-tests.ps1 -All
```

This runs the full backend suite, Flutter analysis and tests, and the
PowerShell tool tests. Run `composer test` in `admin/` separately. Component
commands are in each component's README.

## Releasing

1. Merge to `main` with all checks passing.
2. Deploy the backend by following [deploy.md](deploy.md): back up, apply any
   pending [database migrations](database/README.md#migrations-for-an-existing-database),
   pull, test, restart, check health.
3. Build the signed APK with `./tools/build_karaok.ps1` ([build.md](build.md)).
   Pick the version from the highest one in `dist/` (see `AGENTS.md`).
4. Add the release to [CHANGELOG.md](CHANGELOG.md).

Updating the server does not update phones; users need the new APK.

## Security

- Argon2id password hashes; OTPs and refresh tokens are stored only as hashes.
- Tokens live in platform secure storage on the phone.
- Uploaded audio is deleted after analysis; saved plots are served only after
  an ownership check.
- The Data Administration API needs a high-entropy key and its own
  least-privilege MySQL user, and never accepts raw SQL.
- Secrets belong only in ignored `.env` files. None belong in this repository.

This repository does not declare an open-source license; normal copyright
restrictions apply.
