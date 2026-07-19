# KaraOK API

Flask REST API providing secure authentication, authorization, session management, audit logging, and MySQL persistence for KaraOK.

## Setup

1. Import `../database/schema.sql` into MySQL.
2. Copy `.env.example` to `.env` and set the database credentials and a random `JWT_SECRET` of at least 32 characters.
3. Configure SMTP in `.env` (`SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, and `SMTP_FROM`) for real registration emails.
4. Install and run the API:

```bash
python -m pip install -r requirements.txt
python app.py
```

The local API listens on `http://127.0.0.1:5000` by default. `GET /api/health` verifies both the API and database connection.

## Standalone audio feature analyzer

[`audio_analyzer.py`](audio_analyzer.py) is a standalone command-line utility for
extracting audio features and producing deterministic, no-reference quality
estimates. It is not automatically invoked by the Flask upload endpoints.

The analyzer supports WAV, MP3, FLAC, and OGG files and measures:

- bass and treble RMS plus their percentages of active-frame spectral energy;
- RMS loudness statistics in approximate dBFS (not LUFS);
- spectral flatness and approximate normalized sharpness;
- estimated noise RMS, noise floor in dBFS, and signal-to-noise ratio;
- clipping, crest factor, high-frequency energy, harmonic-to-percussive energy,
  spectral irregularity, and a combined no-reference distortion score.

Noise, SNR, sharpness, and distortion are estimates. The distortion score is not
laboratory THD or THD+N, and the quality status is a configurable deterministic
threshold result rather than a trained classifier.

### Running an analysis

Install the backend dependencies, then run from the repository root:

```powershell
python -m pip install -r backend\requirements.txt
python backend\audio_analyzer.py "audio sample(good)\1.mp3" --output-dir "results\1"
```

The analyzer loads [`audio_analyzer_settings.json`](audio_analyzer_settings.json)
automatically. Supply another settings file with `--settings`, or override the
frame length, hop length, noise percentile, clipping threshold, and bass/treble
cutoffs with their corresponding command-line options.

```powershell
python backend\audio_analyzer.py input.wav `
  --settings backend\audio_analyzer_settings.json `
  --output-dir results\input `
  --frame-length 4096 `
  --hop-length 1024
```

Use `python backend\audio_analyzer.py --help` for the complete command list.

### Settings and fail-safes

The versioned JSON settings file has four sections:

| Section | Purpose | Important defaults |
| --- | --- | --- |
| `analysis` | Feature-extraction windows, frequency bands, silence/clipping limits, and distortion weights | 2,048-sample frames, 512-sample hop, 15th noise percentile, 0.99 clipping threshold |
| `safety` | Resource and damaged-file acceptance limits | 100 MB, 15 minutes, at least 90% and 5 seconds recovered, at least 10 active frames |
| `quality_thresholds` | Deterministic warning/failure boundaries | SNR warning below 10 dB and failure below 5 dB; distortion warning above 20 and failure above 50; clipping failure above 0.5% |
| `failure_behavior` | Output retention, cleanup, failure logging, and quality-failure exit code | retain quality-failure outputs, clean incomplete technical-failure outputs, record errors in CSV, exit 3 on quality failure |

Unknown setting names, malformed JSON, invalid types, unsafe ranges, and reversed
warning/failure thresholds are rejected with clear messages. Each completed
result stores the effective settings snapshot so later changes do not make an
older decision ambiguous.

Before allocating the full analysis arrays, the analyzer checks the file size
and declared duration. It rejects empty, excessively short, silent, oversized,
overlong, non-finite, and insufficiently active recordings. Partially corrupted
files may use a continuous readable prefix only when it meets the configured
duration and recovery-percentage limits; audio on opposite sides of unknown
damage is never joined.

### Generated output

JSON and six PNG visualizations are written to the requested recording folder
with a unique timestamped prefix. CSV data is not duplicated in each subfolder.
Every run appends one flattened row to the nearest shared `results/results.csv`.

```text
results/
|-- results.csv
|-- 1/
|   |-- 1_<timestamp>_analysis.json
|   |-- 1_<timestamp>_waveform.png
|   |-- 1_<timestamp>_spectrogram.png
|   |-- 1_<timestamp>_frequency_spectrum.png
|   |-- 1_<timestamp>_rms_loudness.png
|   |-- 1_<timestamp>_spectral_flatness.png
|   `-- 1_<timestamp>_band_energy_comparison.png
`-- 2/
    `-- ...
```

Technical failures also append a structured CSV row with the category, exception
type, message, input path, and settings path. If JSON or plot generation fails,
only files bearing that run's unique prefix are removed; prior results and the
shared CSV remain intact.

| Exit code | Meaning |
| ---: | --- |
| `0` | Analysis completed and configured quality thresholds passed or produced only warnings |
| `1` | Processing, resource, output, or unexpected technical failure |
| `2` | Invalid input or configuration |
| `3` | Analysis completed and outputs were saved, but a quality failure threshold was crossed |
| `130` | User cancellation |

### Analyzer regression tests

From `backend`, run:

```powershell
python -m unittest discover -s tests -v
```

The suite includes settings validation, quality pass/warning/failure decisions,
pre-decode file-size enforcement, shared CSV behavior, prefix-scoped cleanup,
audio upload validation, and security regressions. A successful run currently
ends with `Ran 17 tests` and `OK`.

## OVHcloud production deployment

Production deployment for Ubuntu 26.04 on OVH VPS `139.99.89.112` is defined in
[`deploy/ovh`](../deploy/ovh) and documented step-by-step in
[`OVH_DEPLOYMENT.md`](../OVH_DEPLOYMENT.md). The deployment uses Nginx HTTPS,
Gunicorn bound to loopback, local MySQL, systemd services, UFW, persistent upload
storage, and automatic database/upload backups. Secrets remain in the ignored
`backend/.env` file on the server.

### Deploying later backend updates

A local `git commit` only records a revision on the development machine, and
`git push` only publishes it to GitHub. Neither action automatically changes the
backend currently running on OVH. Make sure the intended revision has been pushed
to the GitHub `main` branch before starting this procedure.

#### 1. Connect to the VPS

```bash
ssh ubuntu@139.99.89.112
```

The first connection may ask whether to trust the server fingerprint. After a
successful connection, the prompt should resemble `ubuntu@vps-46347102:~$`.

#### 2. Open the deployed repository and inspect it

```bash
cd /opt/karaok/app
pwd
git status --short
```

`pwd` must print `/opt/karaok/app`. A clean `git status --short` prints nothing.
If it lists modified or untracked files, stop and review them; do not use
`git reset --hard` or overwrite production changes. The ignored `backend/.env`
normally does not appear.

#### 3. Back up the production data

```bash
sudo systemctl start karaok-backup.service
sudo systemctl status karaok-backup.service --no-pager
sudo ls -lah /var/backups/karaok
```

The backup service should finish successfully, and the final command should show
recent database/upload backup files. Do not continue with a database migration if
the backup failed.

#### 4. Review and download the new revision

```bash
git fetch origin main
git log --oneline HEAD..origin/main
git pull --ff-only origin main
```

`git log` shows the commits about to be deployed. `git pull` should report either
`Fast-forward` with changed files or `Already up to date.` A merge-conflict or
`Not possible to fast-forward` message means deployment must stop for review.

#### 5. Synchronize backend dependencies

```bash
backend/.venv/bin/python -m pip install -r backend/requirements.txt
```

Normal output contains `Requirement already satisfied` or successful package
installations. Do not restart the service if pip reports an error.

#### 6. Apply only new database migrations

`git pull` does not update MySQL automatically. Read the release notes and apply
only the migration introduced by that release. Never rerun every migration file.
For the temporary-password recovery migration, check the column first:

```bash
sudo mysql -D karaok_db -e "SHOW COLUMNS FROM user LIKE 'requires_password_change';"
```

If this displays a `requires_password_change` row, the migration is already
installed and must not be run again. If it displays no row, run it once:

```bash
sudo mysql < /opt/karaok/app/database/migrations/20260718_temporary_password_recovery.sql
```

No output means the migration succeeded. `ERROR 1060 ... Duplicate column name`
means the column already existed; do not run the migration again.

#### 7. Run the backend tests

```bash
backend/.venv/bin/python -m unittest discover -s backend/tests -v
```

Continue only if the result ends with `OK`. A result containing `FAILED` or
`ERROR` means the service should not be restarted with that revision.

#### 8. Restart and verify the API service

```bash
sudo systemctl restart karaok-api
sudo systemctl status karaok-api --no-pager -l
```

The status must contain `Active: active (running)`. The restart command can return
without an error even if the process exits immediately, which is why the status
check is required.

If the service is not active, inspect its logs:

```bash
sudo journalctl -u karaok-api -n 100 --no-pager
```

#### 9. Verify local and public health

```bash
curl http://127.0.0.1:8000/api/health
curl https://139.99.89.112/api/health
```

Both commands must return a response equivalent to:

```json
{ "db": "connected", "status": "ok" }
```

If the loopback check succeeds but the public check returns `502 Bad Gateway`,
inspect Nginx with `sudo systemctl status nginx --no-pager -l` and
`sudo journalctl -u nginx -n 100 --no-pager`. If the loopback check fails, inspect
`karaok-api` first.

When all checks pass, leave the SSH session with:

```bash
exit
```

Only restart `karaok-api` when backend code, backend dependencies, database
migrations, or production environment settings change. Flutter-only changes
require a new APK but do not require a backend restart.

The production `backend/.env` is intentionally ignored by Git and must be
maintained directly on the VPS; `git pull` does not replace it. Database data and
persistent uploads must remain outside the Git working tree so application updates
cannot replace them. See the complete update, backup, and rollback preparation in
[`OVH_DEPLOYMENT.md`](../OVH_DEPLOYMENT.md).

## Security model

- Passwords are hashed with Argon2id using per-password salts.
- Access tokens expire after 15 minutes by default.
- Opaque refresh tokens are hashed in MySQL, rotated on use, and expire after seven days by default.
- Logout immediately denylists the presented access token and revokes the refresh token.
- Password recovery replaces the account password with a random temporary password, revokes existing refresh sessions, and requires a password change after the next login.
- Protected requests re-check the account's active state and role. Security changes invalidate older access tokens through `security_updated_at`.
- Protected routes derive identity from the access token instead of trusting client-provided user IDs.
- Admin/owner/technician permissions are enforced at each route. Public registration permits owner and technician accounts; the privileged `admin` role must be provisioned administratively.
- Authentication endpoints are rate limited, and sensitive responses use `Cache-Control: no-store`.
- Authentication, authorization failures, password recovery, and data changes are recorded in `audit_log`.
- Login accepts either the account username or verified email address through the `identifier` field.
- Registration uses a six-digit, expiring OTP. The code is emailed through the configured SMTP provider and only its hash is stored in `registration_otp`.

## Security implementation status and decisions

All requested application-level security controls are implemented. The database schema is used as written; the API maps application routes to the existing singular tables such as `assessment`, `user_genre_setting`, `audio_upload`, and `audit_log`.

| Security requirement               | Status                                                        | Implementation                                                                                                                                                                                                                                                                                              | Tools, assets, and approaches used                                                                                                                                                                                                                            | Security decision and rationale                                                                                                                                                                                                                                                                   |
| ---------------------------------- | ------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Authentication and authorization   | Implemented                                                   | Registration requires email OTP verification. Login accepts a username or verified email and returns authenticated tokens. Protected endpoints validate the bearer token and load the current account security state.                                                                                       | Flask routes and decorators; PyJWT bearer tokens using HS256; SMTP email OTP; Python`secrets`; MySQL `user` and `registration_otp` tables; authenticated identity derived from the token `sub` claim.                                                         | Email verification reduces registrations using addresses the caller does not control. Protected operations use identity from the signed token, never a client-supplied`user_id`, preventing impersonation and insecure direct-object references.                                                  |
| Password hashing                   | Implemented                                                   | Passwords are hashed with Argon2id. Registration, password changes, and resets apply the same 12-128 character policy. Successful login rehashes passwords when parameters become outdated.                                                                                                                 | `argon2-cffi` `PasswordHasher` configured for Argon2id; per-password random salts embedded in encoded hashes; constant-time verification; `check_needs_rehash`; MySQL `user.password`.                                                                        | Argon2id is memory-hard and resistant to accelerated cracking. Each encoded hash contains its random salt and parameters. Passwords are never encrypted or stored in plaintext.                                                                                                                   |
| Session management                 | Implemented                                                   | Access JWTs expire after 15 minutes. Random refresh tokens expire after seven days, are stored only as SHA-256 hashes, and rotate transactionally with a row lock. Flutter uses platform secure storage. Logout revokes the refresh token and denylists the presented access token.                         | PyJWT with HS256,`iat`, `nbf`, `exp`, `iss`, `sub`, `role`, and `jti` claims; Python `secrets.token_urlsafe`; `hashlib.sha256`; MySQL `refresh_token` and `revoked_access_token`; `SELECT ... FOR UPDATE`; Flutter `flutter_secure_storage`.                  | Short access-token lifetime limits exposure. Opaque refresh tokens support revocation without storing reusable bearer credentials in plaintext. Rotation with`FOR UPDATE` prevents concurrent reuse.                                                                                              |
| Session invalidation               | Implemented                                                   | Protected requests re-check`is_active`, `role`, `security_updated_at`, and the access-token denylist. Password or role changes invalidate older JWTs. Password changes and resets revoke active refresh sessions.                                                                                           | Live MySQL account-state lookup on every protected request; JWT`iat` comparison; `security_updated_at`; access-token `jti` denylist; refresh-token revocation timestamps; Flask `require_auth` decorator.                                                     | A signed JWT must not preserve access after deactivation, role removal, or credential recovery. Live state checks close that gap without adding schema columns.                                                                                                                                   |
| Role-based access control          | Implemented                                                   | Roles are lowercase`owner`, `technician`, and `admin`. Public registration permits owner and technician accounts and rejects admin. User-directory and central audit-log access require admin. Owner-specific routes require owner; assessment routes allow owner and technician while enforcing ownership. | MySQL`user.role`; JWT `role` claim; Flask `require_auth(*roles)` decorator; role allowlists; ownership predicates using authenticated `g.user_id`; explicit `SELF_REGISTER_ROLES`.                                                                            | Owner and technician are legitimate application account types. Administrator is privileged and must be assigned through a controlled process, preventing self-service privilege escalation.                                                                                                       |
| Input validation and sanitization  | Implemented                                                   | JSON bodies must be objects. Text is trimmed and whitespace-normalized, email is normalized and format-checked, passwords and numbers have bounds, and roles/status values use allowlists. SQL uses connector parameters. IDs use typed routes and ownership predicates.                                    | Flask JSON parsing and typed route converters; Python regular expressions, normalization helpers, bounds, and allowlists; MySQL Connector parameterized queries; Werkzeug`secure_filename`; Mutagen audio validation; request-size and file-extension limits. | Server validation is authoritative because clients can be bypassed. Normalization gives consistent values, allowlists prevent unexpected states, and parameterized SQL prevents inputs becoming executable SQL. JSON output avoids treating destructive HTML filtering as universal sanitization. |
| Forgot/reset password              | Implemented                                                   | Requests are rate-limited and return a uniform response. A random temporary password replaces the old password, active refresh sessions are revoked, and the temporary password is emailed. Login requires immediate password replacement and other protected operations are blocked until it is completed. | Flask-Limiter; Python`secrets` and `SystemRandom`; Argon2id hashing; SMTP with `EmailMessage` and STARTTLS; MySQL `requires_password_change`; session revocation; uniform API responses; mandatory-change screen in Flutter.                                  | Uniform responses reduce enumeration. Forced replacement limits the temporary credential to account recovery and prevents normal application use until the user establishes a private password.                                                                                                   |
| Audit logging                      | Implemented                                                   | Authentication outcomes, refresh/logout, access denial, validation failure, password recovery, registration, password changes, and mutations record actor, action, result, resource, IP, user agent, details, and server time. Audit-log access requires admin.                                             | Central`audit()` helper; MySQL `audit_log`; UTC server timestamps; authenticated actor ID; client IP and user-agent metadata; parameterized inserts; admin-only audit endpoint; secret-field exclusion.                                                       | Security events are separate rows so history is not overwritten by current entity state. Passwords, OTPs, temporary passwords, and bearer tokens are excluded from logs.                                                                                                                          |
| Accountability and non-repudiation | Application support implemented; deployment controls required | The application records attributable events and ignores forwarded IP headers unless configured behind a trusted proxy. Production must deny audit updates/deletes and export records to immutable or append-only storage.                                                                                   | `audit_log`; JWT identity; trusted-proxy configuration with Werkzeug `ProxyFix`; Nginx; database privilege separation; protected backups and recommended off-server append-only log export.                                                                   | A mutable database controlled by one operator cannot alone establish strong or legal non-repudiation. That requires separation of duties, restricted privileges, trustworthy attribution, retention controls, and an independently protected log destination.                                     |
| Documentation and verification     | Implemented                                                   | This section records the control, mechanism, and reason for every feature. Regression tests cover password policy, normalization, token hashing, JWT claims, technician registration, and rejection of public admin registration.                                                                           | `backend/README.md`; `OVH_DEPLOYMENT.md`; `database/schema.sql`; Python `unittest`; Flask test client; `flutter analyze`; `flutter test`; production health checks.                                                                                           | Tests prevent silent policy regression, while documentation makes code assumptions and deployment responsibilities explicit.                                                                                                                                                                      |

### RBAC matrix

| Capability                                         | Owner | Technician | Admin |
| -------------------------------------------------- | :---: | :--------: | :---: |
| Self-register with email verification              |  Yes  |    Yes     |  No   |
| Sign in, refresh, log out, and change own password |  Yes  |    Yes     |  Yes  |
| Read and manage own assessments                    |  Yes  |    Yes     |  No   |
| Read genre settings                                |  Yes  |    Yes     |  No   |
| Save owner genre settings                          |  Yes  |     No     |  No   |
| Read and create owner upload records               |  Yes  |     No     |  No   |
| List users                                         |  No   |     No     |  Yes  |
| Read centralized audit logs                        |  No   |     No     |  Yes  |

Administrator accounts must be provisioned through a controlled operational process. Never expose an unauthenticated endpoint that assigns the `admin` role.

## Database design

The active schema is [`database/schema.sql`](../database/schema.sql). It keeps the original database model as its foundation and appends only tables needed by the security and application workflows. [`database/schema_original.sql`](../database/schema_original.sql) is retained as the reference copy of the original design.

### Original foundation tables

| Table                     | What it stores                                                                                                                                                                                                 | How the application uses it                                                                                                                                                                                                                                                                    |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `user`                    | One account per row: login name, password hash, email, role, active status, mandatory-password-change state, security-update time, and creation time. The`user_id` value is the identity used by foreign keys. | Authentication looks up the account by`username` or `email`; the `password` column stores the Argon2id hash; `requires_password_change` restricts temporary-password sessions; `role` is re-checked on protected requests. Application roles are lowercase `owner`, `technician`, and `admin`. |
| `genre_preset`            | Shared recommended sound values for a genre, including bass, treble, loudness, sharpness, and flatness.`genre_name` is unique so one shared preset cannot be accidentally duplicated.                          | The analysis result points to a preset through`preset_id`. This preserves which recommendation was used for an assessment.                                                                                                                                                                     |
| `audio_quality_threshold` | Named quality rules: maximum noise, maximum distortion, and minimum quality score.                                                                                                                             | An analysis result points to the threshold used through`threshold_id`, making the decision reproducible if thresholds change later.                                                                                                                                                            |
| `assessment`              | The uploaded-audio job itself: owner (`user_id`), file path, processing status, date, external API reference, processing time, display name, duration, and result status.                                      | This is the parent record for one audio assessment. Its lifecycle is represented by`assessment_status`; application metadata is stored on the same row because it depends directly on `assessment_id`; detailed measurements belong in `audio_analysis_result`.                                |
| `audio_analysis_result`   | The measured output for one assessment: quality score, noise, distortion, recommended sound values, waveform path, and spectrogram path.                                                                       | `assessment_id` is unique, so one assessment has at most one detailed result. `threshold_id` and `preset_id` document the rules and recommendation used for that result.                                                                                                                       |

### Additive tables

These tables do not replace the original tables. They add capabilities that the original design did not contain.

| Table                  | What it stores                                                                                                                                                                            | Why it is separate                                                                                                                                              |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `refresh_token`        | A hash of each long-lived refresh token, its owner, expiry, revocation time, client IP, and user agent.                                                                                   | One user may sign in on multiple devices. A separate row per session supports rotation and logout revocation without storing a bearer token in plaintext.       |
| `revoked_access_token` | The JWT`jti`, owner, expiry, and revocation time for access tokens invalidated before natural expiry.                                                                                     | Access tokens are normally stateless. This small denylist allows logout and emergency revocation while retaining short-lived tokens.                            |
| `audit_log`            | Security and accountability events such as login failures, authorization failures, password resets, and data changes, including actor, action, result, client information, and timestamp. | Audit records are append-only events. They should not be columns on`user` or `assessment`, because one actor can create many events across many resource types. |
| `user_genre_setting`   | A user's saved genre adjustment, optionally linked to the shared`genre_preset`, including volume and tone values.                                                                         | Shared presets and user-specific overrides have different ownership and lifecycles, so overrides belong in a child table.                                       |
| `audio_upload`         | An upload record with owner, optional assessment, filename, genre label, score, status, and creation time.                                                                                | An upload may exist before processing creates an`assessment`; the nullable relationship supports that workflow without changing the original assessment table.  |

### Relationships and normalization

The schema uses `user.user_id` as the account key. `assessment.user_id`, security tables, and upload records reference it with foreign keys. `audio_analysis_result` references `assessment`, `audio_quality_threshold`, and `genre_preset`, while upload records reference `assessment` when applicable. Account security state and assessment application metadata are stored directly on their one-to-one parent rows.

The design is approximately in third normal form: each table describes one subject or event, non-key attributes depend on that table's key, and cross-table relationships are represented by foreign keys. `user_security` and `assessment_metadata` were merged because their columns depended directly and exclusively on `user_id` and `assessment_id`, respectively. Historical measurements such as `quality_score`, `noise_level`, and `bass` intentionally remain on `audio_analysis_result`; they are snapshots of a completed assessment and must not change when a newer preset or threshold is created. That is controlled historical duplication, not an accidental normalization violation.

The role column is a `VARCHAR`, not an enum, so roles can be introduced without changing the schema. The application uses lowercase `owner`, `technician`, and `admin`; legacy mixed-case values must be normalized.

`CREATE DATABASE` and `CREATE TABLE` statements are initialization statements, not migrations. Back up existing data before applying this file to an existing database, and add future changes through explicit migration scripts.

Password recovery uses the same SMTP settings as registration. Requests return a uniform response to reduce account enumeration, replace the old password with a random temporary password, revoke refresh sessions, and email that temporary credential. After login, `requires_password_change` sends the user directly to the mandatory change-password screen and blocks other protected API operations. The account-menu flow separately requires the current password.

When `DEV_MODE=true`, the forgot-password request endpoint is exempt from its production rate limit for local testing. Set `DEV_MODE=false` before deployment; production requests are limited to three per IP address per hour.

### Audit integrity and proxy trust

Audit records are written separately from business transactions so a failed audit write does not corrupt application data. They provide accountability metadata, but a mutable application database alone cannot guarantee legal non-repudiation. In production, grant the API database identity INSERT/SELECT-only access to `audit_log`, deny application UPDATE/DELETE privileges, and export logs to an access-controlled immutable or append-only logging service. Restrict audit-log reading to `admin` accounts.

Client IP addresses come directly from the transport peer. Forwarded client-IP headers are not trusted.

Run all backend regression tests from `backend` with:

```bash
python -m unittest discover -s tests -v
```

## Endpoints

Public endpoints:

- `GET /api/health`
- `POST /api/auth/register`
- `POST /api/auth/login`
- `POST /api/auth/refresh`
- `POST /api/auth/logout`
- `POST /api/auth/forgot-password`

`POST /api/auth/login` accepts an `identifier` containing either the username or email address, together with `password`.

Authenticated endpoints:

- `POST /api/auth/change-password` — owner, technician, or admin changing their own password
- `GET /api/users` — admin only
- `GET|POST /api/audio-tests` — owner or technician, scoped to the authenticated user
- `GET|DELETE /api/audio-tests/<id>` — owner or technician, ownership enforced
- `GET /api/genre-settings` — owner or technician
- `POST /api/genre-settings` — owner only
- `GET /api/audio-uploads` — owner upload history, scoped to the authenticated user
- `POST /api/audio-uploads` — owner or technician; authenticated `multipart/form-data` upload using file field `audio`, required `duration_seconds` (1–300), and optional `genre`. Accepted extensions are WAV, MP3, M4A, AAC, OGG, and FLAC; the default maximum is 25 MB. A successful request returns HTTP 201 with the upload and assessment IDs and a `Pending` status.
- `GET /api/audit-logs` — admin only

Send the access token on protected requests:

```http
Authorization: Bearer <access-token>
```

## Production checklist

- Use a dedicated least-privilege MySQL account instead of `root`.
- Rotate all development credentials and signing secrets.
- Set `FLASK_DEBUG=false` and use a production WSGI server.
- Terminate TLS at a trusted reverse proxy and allow only HTTPS.
- Restrict `CORS_ORIGINS` to the deployed application origins.
- Configure Flask-Limiter with Redis or another shared storage backend.
- Connect password recovery to verified email delivery without returning tokens in API responses.

## Email-verified registration

Registration is two-step: `POST /api/auth/register` validates the account details and sends a six-digit OTP through SMTP; `POST /api/auth/register/verify` accepts the email and code and then creates the account. The Flutter client presents verification on a dedicated OTP screen after the registration form is submitted. The code is hashed before storage and is never logged in plaintext.

Configure `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM`, and `REGISTRATION_OTP_MINUTES` in `backend/.env`. The SQL seed section adds baseline genre presets and quality thresholds with `INSERT IGNORE`, so it can be rerun safely.

`registration_otp` is a staging table and intentionally has no foreign key to `user`: no user row exists before verification. When verification succeeds, the API inserts the pending account into `user` and deletes the staging row in the same database transaction. Invalid codes increment `attempts`, and verification is rejected after five failed attempts.
