# KaraOK

KaraOK is a Flutter application for assessing karaoke audio quality and managing recommended sound settings. It provides separate experiences for karaoke owners and audio technicians, with a Flask REST API and MySQL database for accounts, saved tests, genre settings, and upload records.

Repository: [github.com/jbl2023-2879-91296-cpu/KaraOK](https://github.com/jbl2023-2879-91296-cpu/KaraOK)

## Application features

- Owner and technician account registration and username-or-email sign-in
- Dedicated email OTP verification screen after registration details are submitted
- Argon2id password hashing, expiring token sessions, logout revocation, and role-based API access
- Single-use, expiring forgot/reset-password tokens
- Server-side input validation, login rate limiting, and security audit logs
- Guest access for trying the application without saving a session
- Role-specific home screens and result histories
- Guided audio-test flow with recording, processing, score, and detailed-report screens
- Quality results including noise and distortion indicators
- Searchable genre selection for owner tests
- Recommended volume, bass, treble, flatness, and sharpness settings by genre
- Audio-upload workflow and saved upload records
- Saved audio-test history with individual result lookup and deletion

> [!NOTE]
> The current audio recording, processing, and upload screens simulate parts of the analysis workflow. They do not yet capture, upload, or analyze real audio files.

## Technology stack

- **Client:** Flutter and Dart
- **HTTP client:** `package:http`
- **API:** Python, Flask, and Flask-CORS
- **Database:** MySQL through `mysql-connector-python`

## Repository structure

```text
KaraOK/
|-- backend/
|   |-- app.py               # Flask API
|   |-- requirements.txt     # Python dependencies
|   `-- README.md            # Backend endpoint notes
|-- database/
|   `-- schema.sql            # MySQL schema
`-- frontend/
    `-- karaok_app/
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

```bash
cd frontend/karaok_app
flutter pub get
flutter run
```

To select a target explicitly:

```bash
flutter devices
flutter run -d chrome
```

## API overview

The Flutter client uses these REST resources:

| Method | Endpoint | Purpose |
|---|---|---|
| `GET` | `/api/health` | Check API and database availability |
| `POST` | `/api/auth/register` | Register an owner or technician |
| `POST` | `/api/auth/login` | Authenticate with a username or email address |
| `POST` | `/api/auth/refresh` | Rotate a refresh token and issue a new session pair |
| `POST` | `/api/auth/logout` | Revoke access and refresh tokens |
| `POST` | `/api/auth/forgot-password` | Request a single-use reset token |
| `POST` | `/api/auth/reset-password` | Reset a password and revoke existing sessions |
| `GET`, `POST` | `/api/users` | List or create users |
| `GET`, `POST` | `/api/audio-tests` | List or save audio-test results |
| `GET`, `DELETE` | `/api/audio-tests/<id>` | Retrieve or delete a test result |
| `GET`, `POST` | `/api/genre-settings` | Retrieve or save genre settings |
| `GET`, `POST` | `/api/audio-uploads` | List or save upload records |
| `GET` | `/api/audit-logs` | Review recent security and data-change events (owner only) |

## Development checks

Run these commands from `frontend/karaok_app` before submitting changes:

```bash
flutter analyze
flutter test
```

## Security and deployment notes

The repository is configured for local development. Before production use:

- Replace the Flask development server with a production WSGI server.
- Set `EXPOSE_RESET_TOKEN=false` and connect reset requests to an email provider.
- Use HTTPS for all API traffic.
- Replace the in-memory rate-limit store with Redis or another shared persistent store.
- Rotate the development MySQL and JWT secrets before deployment.

## Project status

KaraOK is under active development. Secure authentication, session rotation/revocation, RBAC, input validation, password reset, and audit logging are implemented. Real audio capture/analysis, reset-email delivery, and production deployment configuration remain development work.

## Security and database documentation

The backend provides Argon2id password hashing, token-based sessions, role-based API authorization, password reset tokens, rate limiting, input validation, and audit logging. See [`backend/README.md`](../../backend/README.md) for the security model and table-by-table schema explanation.

Registration asks for a username instead of a full name. After submitting the form, the app opens a separate verification screen where the user enters the six-digit OTP delivered to the supplied email address. The backend must have SMTP settings configured before registration emails can be sent. Login accepts either the username or email address.

The original design is retained at [`database/schema_original.sql`](../../database/schema_original.sql). The active [`database/schema.sql`](../../database/schema.sql) keeps those original foundation tables and adds only the missing security/application tables. The one-to-one `user_security` and `assessment_metadata` additions are now merged into `user` and `assessment`, respectively. See the backend README for longer onboarding descriptions of every table, its foreign keys, and the reason each additive table exists.

See [`CHANGELOG.md`](../../CHANGELOG.md) for the dated list of security, API, client, and schema changes.

## Email registration

Registration asks for a username instead of a full name, then opens a dedicated screen for the six-digit OTP delivered to the supplied email address. SMTP must be configured in the backend before real registration emails can be sent. The visible registration flow is role-neutral; roles remain an internal authorization concern. Users can subsequently sign in with either their username or email address.
