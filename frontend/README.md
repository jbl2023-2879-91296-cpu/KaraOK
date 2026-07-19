# KaraOK

KaraOK is a Flutter application for assessing karaoke audio quality and managing recommended sound settings. It provides separate experiences for karaoke owners and audio technicians, with a Flask REST API and MySQL database for accounts, saved tests, genre settings, and upload records.

Repository: [github.com/jbl2023-2879-91296-cpu/KaraOK](https://github.com/jbl2023-2879-91296-cpu/KaraOK)

## Application features

- Owner and technician account registration and username-or-email sign-in
- Dedicated email OTP verification screen after registration details are submitted
- Argon2id password hashing, expiring token sessions, logout revocation, and role-based API access
- Email-delivered temporary passwords with a mandatory in-app password change
- Server-side input validation, login rate limiting, and security audit logs
- Guest access for trying the application without saving a session
- Role-specific home screens and result histories
- Separate audio-quality evaluation and settings-suggestion entry flows, each
  supporting microphone recording or audio-file selection
- Shared upper-left navigation drawer for Home, Reports, account Settings, and
  session-aware Sign In or Log Out actions across the main app screens
- Settings displays the signed-in user's username, email, and account type
- Quality results including noise and distortion indicators
- Searchable genre selection for owner tests
- Recommended volume, bass, treble, flatness, and sharpness settings by genre
- Audio-upload workflow and saved upload records
- Saved audio-test history with individual result lookup and deletion
- Standalone Python extraction of bass, treble, loudness, flatness, sharpness,
  estimated noise/SNR, and no-reference distortion indicators
- NumPy-derived empirical good-audio ranges, per-feature scoring, a weighted
  overall score, and separate worst-feature reporting

Microphone recordings are saved under the application's private documents
directory so a successful upload does not delete the local recording. Selected
files are copied into temporary staging on native platforms. In Flutter Web,
browser-selected files remain in memory, are previewed through their Blob URL,
and are submitted as multipart bytes with the original filename. The API stores
the upload, runs `audio_analyzer.py`, and returns a temporary raw
`analysis_dump` that the app displays for validation.

The repository now includes a complete standalone analyzer at
[`backend/audio_analyzer.py`](../backend/audio_analyzer.py). Authenticated audio
uploads invoke it through the Flask API; it can also be run independently from
the command line.

### Running the standalone analyzer

From the repository root:

```powershell
python -m pip install -r backend\requirements.txt
python backend\audio_analyzer.py "audio sample(good)\1.mp3" --output-dir "results\1"
```

Per-recording JSON reports and plots are stored in the selected output folder.
All analyses append to `results/results.csv`. Adjustable analysis, safety, and
quality limits are defined in
[`backend/audio_analyzer_settings.json`](../backend/audio_analyzer_settings.json).
See the [backend analyzer documentation](../backend/README.md#standalone-audio-feature-analyzer)
for measurements, fail-safes, recovery behavior, outputs, and exit codes.

### Empirical good-audio scoring

The standalone analyzer remains responsible for feature extraction. The
separate [`backend/good_audio_thresholds`](../backend/good_audio_thresholds/README.md)
package uses the completed known-good recordings in `results/results.csv` to
derive provisional ranges for integrated loudness, bass energy, treble energy,
normalized sharpness, and spectral flatness.

Regenerate the checked threshold artifact after the reference dataset changes:

```powershell
backend\.venv\Scripts\python.exe backend\good_audio_thresholds\derive_thresholds.py
```

The feature interpretation is:

- inside P05-P95, including the boundaries: `good`;
- outside P05-P95 but inside the observed minimum-maximum envelope:
  `good_but_needs_improvement`;
- strictly outside the observed envelope: `bad`;
- missing or non-finite: `not_evaluated`.

Each feature receives a continuous score with 100 at the median, 80 at P05/P95,
and 50 at the observed minimum/maximum. The overall score is split across
loudness 30%, bass 25%, treble 20%, sharpness 15%, and flatness 10%. Its status
is `good` at 80 or higher, `good_but_needs_improvement` from 50 to less than 80,
and `bad` below 50. The most severe individual feature is also returned as
`worst_feature_status`; it is a separate warning and does not replace the
weighted overall status.

The generated
[`good_audio_thresholds.json`](../backend/good_audio_thresholds/good_audio_thresholds.json)
records the exact NumPy statistics, bootstrap intervals, correlations, recovery
sensitivity, selected analysis IDs, and source CSV SHA-256. These bounds come
from 30 good-only phone recordings, so `bad` currently means outside that
observed envelope rather than a validated perceptual diagnosis.

## Technology stack

- **Client:** Flutter and Dart
- **HTTP client:** `package:http`
- **API:** Python, Flask, and Flask-CORS
- **Audio analysis:** Librosa, NumPy, SciPy, SoundFile, Matplotlib, and Pandas
- **Database:** MySQL through `mysql-connector-python`

## Repository structure

```text
KaraOK/
|-- backend/
|   |-- app.py                         # Flask API
|   |-- audio_analyzer.py              # Standalone feature and quality analysis CLI
|   |-- audio_analyzer_settings.json   # Adjustable analysis and fail-safe limits
|   |-- good_audio_thresholds/         # Empirical range derivation and scoring
|   |-- requirements.txt               # Python dependencies
|   |-- tests/                         # Backend and analyzer regression tests
|   `-- README.md                      # API and analyzer documentation
|-- database/
|   `-- schema.sql            # MySQL schema
`-- frontend/
    |-- lib/
    |   |-- screens/      # Application screens and flows
    |   |-- services/     # API access and user session state
    |   `-- widgets/      # Shared UI components
    |-- test/              # Flutter tests
    `-- pubspec.yaml       # Flutter dependencies and metadata
```

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) compatible with Dart `^3.12.2`
- Python 3 with `pip`
- MySQL Server
- Chrome, an Android emulator, or another Flutter-supported target

Confirm the local toolchain before setup:

```bash
flutter doctor
python --version
mysql --version
```

## Local setup

### 1. Clone the repository

```bash
git clone https://github.com/jbl2023-2879-91296-cpu/KaraOK.git
cd KaraOK
```

### 2. Configure MySQL

Create the database and security tables by importing [`database/schema.sql`](../../database/schema.sql). Copy [`backend/.env.example`](../../backend/.env.example) to `backend/.env`, set the MySQL credentials, and generate a random `JWT_SECRET` of at least 32 characters. The real `.env` file is ignored by Git.

For production, create the least-privilege `karaok_app` MySQL account described at the bottom of `schema.sql`; do not run the API as MySQL `root`.

### 3. Install and run the API

From the repository root:

```bash
cd backend
python -m pip install -r requirements.txt
python app.py
```

The development API runs at `http://localhost:5000`. Check its database connection at `http://localhost:5000/api/health`.

### 4. Configure the client API address

Edit `baseUrl` in [`lib/services/api_service.dart`](lib/services/api_service.dart) for the target device:

| Target | API base URL |
|---|---|
| Android emulator | `http://10.0.2.2:5000/api` |
| Chrome or Windows on the same computer | `http://localhost:5000/api` (default) |
| Physical device | `http://<computer-lan-ip>:5000/api` |

Pass a non-default address without changing source code:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000/api
```

A physical device must be on the same network as the API host, and the host firewall must allow inbound traffic to port `5000`.

### 5. Install Flutter packages and run

For Android Studio, open the `frontend` directory rather than only `frontend/android`. Enable the Flutter and Dart plugins, select the Flutter SDK, start an emulator, and choose the shared **KaraOK Android Emulator** run configuration.

That configuration supplies `API_BASE_URL=http://10.0.2.2:5000/api`; the Android emulator maps `10.0.2.2` to the development computer. The debug manifest permits local HTTP traffic, while release builds remain protected. Run Flask on `0.0.0.0:5000`. For a physical device, replace `10.0.2.2` with the computer's LAN IP.

```bash
cd frontend
flutter pub get
flutter run
```

To select a target explicitly:

```bash
flutter devices
flutter run -d chrome
```

## Build an Android APK

The complete, reproducible command sequence for debug and release APKs is in
[`BUILDING_APK.md`](../BUILDING_APK.md). From the repository root, the shortest
debug build is:

```bash
cd frontend
flutter pub get
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:5000/api
```

The generated file is `frontend/build/app/outputs/flutter-apk/app-debug.apk`.
Use a LAN-accessible HTTPS API URL instead of `10.0.2.2` when building for a
physical device. The current release build uses Android's debug signing key and
is intended only for testing; configure a private release keystore before
publishing the application.

## API overview

The Flutter client uses these REST resources:

| Method | Endpoint | Purpose |
|---|---|---|
| `GET` | `/api/health` | Check API and database availability |
| `POST` | `/api/auth/register` | Register an owner or technician |
| `POST` | `/api/auth/login` | Authenticate with a username or email address |
| `POST` | `/api/auth/refresh` | Rotate a refresh token and issue a new session pair |
| `POST` | `/api/auth/logout` | Revoke access and refresh tokens |
| `POST` | `/api/auth/forgot-password` | Generate and email a temporary password |
| `POST` | `/api/auth/change-password` | Change the authenticated user's password |
| `GET`, `POST` | `/api/users` | List or create users |
| `GET`, `POST` | `/api/audio-tests` | List or save audio-test results |
| `GET`, `DELETE` | `/api/audio-tests/<id>` | Retrieve or delete a test result |
| `GET`, `POST` | `/api/genre-settings` | Retrieve or save genre settings |
| `GET`, `POST` | `/api/audio-uploads` | List uploads or upload and analyze an audio file |
| `GET` | `/api/audio-uploads/<id>/analysis-dump` | Retrieve the authenticated user's raw analyzer dump |
| `GET` | `/api/audit-logs` | Review recent security and data-change events (owner only) |

## Development checks

Run these commands from `frontend` before submitting changes:

```bash
flutter analyze
flutter test
```

Run the backend and empirical-threshold regressions from `backend`:

```powershell
python -m unittest discover -s tests -v
```

The current backend suite contains 29 passing tests, including eight tests for
cohort selection, exact boundary behavior, continuous scoring, configurable
weights, missing measurements, and deterministic threshold generation.

## Security and deployment notes

The repository is configured for local development. Before production use:

- Replace the Flask development server with a production WSGI server.
- Keep SMTP credentials private and use a dedicated provider password for recovery email delivery.
- Use HTTPS for all API traffic.
- Replace the in-memory rate-limit store with Redis or another shared persistent store.
- Rotate the development MySQL and JWT secrets before deployment.

The configured OVHcloud production endpoint is `https://139.99.89.112/api`. See
[`DeployOVH.md`](../DeployOVH.md) for server provisioning, HTTPS, and
the exact release build command.

## Project status

KaraOK is under active development. Secure authentication, session
rotation/revocation, RBAC, input validation, password recovery, audit logging,
server-triggered audio feature extraction, inspectable analysis dumps, and
empirical good-audio scoring are implemented. Background job-queue processing,
broader labeled audio validation, and production release hardening remain
development work.

## Security and database documentation

The backend provides Argon2id password hashing, token-based sessions, role-based API authorization, forced temporary-password recovery, rate limiting, input validation, and audit logging. See [`backend/README.md`](../../backend/README.md) for the security model and table-by-table schema explanation.

Registration asks for a username instead of a full name. After submitting the form, the app opens a separate verification screen where the user enters the six-digit OTP delivered to the supplied email address. The backend must have SMTP settings configured before registration emails can be sent. Login accepts either the username or email address.

The original design is retained at [`database/schema_original.sql`](../../database/schema_original.sql). The active [`database/schema.sql`](../../database/schema.sql) keeps those original foundation tables and adds only the missing security/application tables. The one-to-one `user_security` and `assessment_metadata` additions are now merged into `user` and `assessment`, respectively. See the backend README for longer onboarding descriptions of every table, its foreign keys, and the reason each additive table exists.

See [`CHANGELOG.md`](../../CHANGELOG.md) for the dated list of security, API, client, and schema changes.

## Email registration

Registration asks for a username instead of a full name, then opens a dedicated screen for the six-digit OTP delivered to the supplied email address. SMTP must be configured in the backend before real registration emails can be sent. The visible registration flow is role-neutral; roles remain an internal authorization concern. Users can subsequently sign in with either their username or email address.
