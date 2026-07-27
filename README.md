# KaraOK

KaraOK is a Flutter application for evaluating karaoke audio quality. A Flask
API analyzes uploaded or recorded audio, grades five empirical features, stores
authenticated-user history in MySQL, and produces real Matplotlib waveform and
spectrogram reports.

## Current application flow

- The app opens directly in guest mode; login is optional at startup.
- Guests receive three successful audio evaluations on the device.
- Signed-in users can log in with either their username or verified email.
- Public registration creates only regular `user` accounts.
- Home, Records, and Settings are persistent bottom-navigation destinations.
- Settings allows profile editing while keeping the email address read-only.
- Completed results include a score, feature grading, noise and distortion
  measurements, and generated waveform and spectrogram reports.

## Technology

| Layer | Technology |
| --- | --- |
| Client | Flutter and Dart |
| API | Python, Flask, JWT, Argon2id |
| Audio analysis | Librosa, NumPy, SciPy, Matplotlib, Pandas |
| Database | MySQL |
| Production | Gunicorn, Nginx, systemd |

## Repository layout

```text
KaraOK/
|-- backend/          Flask API, analyzer, thresholds, and tests
|-- frontend/         Flutter application and widget tests
|-- database/         Fresh-install MySQL schema
|-- deploy/ovh/       Production service and web-server configuration
|-- CHANGELOG.md      User-visible implementation history
`-- README.md         Public project documentation
```

See the component documentation for details:

- [Backend](backend/README.md)
- [Frontend](frontend/README.md)
- [Database](database/README.md)

## Prerequisites

- Flutter with Dart `3.12.2` or later in the supported SDK range
- Python `3.13` and `venv`
- MySQL 8.x
- FFmpeg and libsndfile for supported audio decoding

## Quick start

### 1. Create the database

Import the authoritative fresh-install schema into an empty MySQL instance:

```powershell
mysql -u root -p < database\schema.sql
```

### 2. Run the API

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
```

Edit `backend/.env` with local database, JWT, SMTP, CORS, and storage values.
Never commit that file. Then start the API:

```powershell
.\.venv\Scripts\python.exe run.py
```

The default health endpoint is `http://127.0.0.1:5000/api/health`.

### 3. Run Flutter

```powershell
cd frontend
flutter pub get
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:5000/api
```

For an Android emulator, use `http://10.0.2.2:5000/api` instead of localhost.

## Testing

Run the lightweight client checks:

```powershell
cd frontend
flutter analyze
flutter test
```

Run the backend suite:

```powershell
cd backend
.\.venv\Scripts\python.exe -m unittest discover -s tests -p "test_*.py" -v
```

## Security and publication

- Passwords use Argon2id hashes.
- OTPs and tokens are never stored in plaintext.
- Uploaded audio is temporary and deleted after processing.
- Saved visualizations are served only after assessment ownership checks.
- API errors are returned as JSON.
- Secrets belong only in ignored environment files or a production secret
  manager. No real credentials should appear in this public README.

This repository does not currently declare an open-source license. Unless a
license is added, normal copyright restrictions apply.
