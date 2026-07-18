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
backend currently running on OVH. Deploy the pushed revision from the VPS:

```bash
ssh ubuntu@139.99.89.112
cd /opt/karaok/app
git status --short
git pull --ff-only origin main
backend/.venv/bin/python -m pip install -r backend/requirements.txt
backend/.venv/bin/python -m unittest discover -s backend/tests -v
sudo systemctl restart karaok-api
sudo systemctl status karaok-api --no-pager
curl http://127.0.0.1:8000/api/health
curl https://139.99.89.112/api/health
```

Only restart `karaok-api` when backend code, backend dependencies, or production
environment settings change. Flutter-only changes require a new APK but do not
require a backend restart. Before pulling, confirm that `git status --short` is
empty; do not discard server-side changes without reviewing them.

The production `backend/.env` is intentionally ignored by Git and must be
maintained directly on the VPS. A pull does not migrate MySQL automatically, so
apply reviewed schema migrations separately and back up the database first.
Database data and persistent uploads must remain outside the Git working tree so
that application updates cannot replace them. See the update and backup procedure
in [`OVH_DEPLOYMENT.md`](../OVH_DEPLOYMENT.md) before deploying a new revision.

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

| Security requirement | Status | Implementation | Security decision and rationale |
|---|---|---|---|
| Authentication and authorization | Implemented | Registration requires email OTP verification. Login accepts a username or verified email and returns authenticated tokens. Protected endpoints validate the bearer token and load the current account security state. | Email verification reduces registrations using addresses the caller does not control. Protected operations use identity from the signed token, never a client-supplied `user_id`, preventing impersonation and insecure direct-object references. |
| Password hashing | Implemented | Passwords are hashed with Argon2id. Registration, password changes, and resets apply the same 12-128 character policy. Successful login rehashes passwords when parameters become outdated. | Argon2id is memory-hard and resistant to accelerated cracking. Each encoded hash contains its random salt and parameters. Passwords are never encrypted or stored in plaintext. |
| Session management | Implemented | Access JWTs expire after 15 minutes. Random refresh tokens expire after seven days, are stored only as SHA-256 hashes, and rotate transactionally with a row lock. Flutter uses platform secure storage. Logout revokes the refresh token and denylists the presented access token. | Short access-token lifetime limits exposure. Opaque refresh tokens support revocation without storing reusable bearer credentials in plaintext. Rotation with `FOR UPDATE` prevents concurrent reuse. |
| Session invalidation | Implemented | Protected requests re-check `is_active`, `role`, `security_updated_at`, and the access-token denylist. Password or role changes invalidate older JWTs. Password changes and resets revoke active refresh sessions. | A signed JWT must not preserve access after deactivation, role removal, or credential recovery. Live state checks close that gap without adding schema columns. |
| Role-based access control | Implemented | Roles are lowercase `owner`, `technician`, and `admin`. Public registration permits owner and technician accounts and rejects admin. User-directory and central audit-log access require admin. Owner-specific routes require owner; assessment routes allow owner and technician while enforcing ownership. | Owner and technician are legitimate application account types. Administrator is privileged and must be assigned through a controlled process, preventing self-service privilege escalation. |
| Input validation and sanitization | Implemented | JSON bodies must be objects. Text is trimmed and whitespace-normalized, email is normalized and format-checked, passwords and numbers have bounds, and roles/status values use allowlists. SQL uses connector parameters. IDs use typed routes and ownership predicates. | Server validation is authoritative because clients can be bypassed. Normalization gives consistent values, allowlists prevent unexpected states, and parameterized SQL prevents inputs becoming executable SQL. JSON output avoids treating destructive HTML filtering as universal sanitization. |
| Forgot/reset password | Implemented | Requests are rate-limited and return a uniform response. A random temporary password replaces the old password, active refresh sessions are revoked, and the temporary password is emailed. Login requires immediate password replacement and other protected operations are blocked until it is completed. | Uniform responses reduce enumeration. Forced replacement limits the temporary credential to account recovery and prevents normal application use until the user establishes a private password. |
| Audit logging | Implemented | Authentication outcomes, refresh/logout, access denial, validation failure, password recovery, registration, password changes, and mutations record actor, action, result, resource, IP, user agent, details, and server time. Audit-log access requires admin. | Security events are separate rows so history is not overwritten by current entity state. Passwords, OTPs, temporary passwords, and bearer tokens are excluded from logs. |
| Accountability and non-repudiation | Application support implemented; deployment controls required | The application records attributable events and ignores forwarded IP headers unless configured behind a trusted proxy. Production must deny audit updates/deletes and export records to immutable or append-only storage. | A mutable database controlled by one operator cannot alone establish strong or legal non-repudiation. That requires separation of duties, restricted privileges, trustworthy attribution, retention controls, and an independently protected log destination. |
| Documentation and verification | Implemented | This section records the control, mechanism, and reason for every feature. Regression tests cover password policy, normalization, token hashing, JWT claims, technician registration, and rejection of public admin registration. | Tests prevent silent policy regression, while documentation makes code assumptions and deployment responsibilities explicit. |

### RBAC matrix

| Capability | Owner | Technician | Admin |
|---|:---:|:---:|:---:|
| Self-register with email verification | Yes | Yes | No |
| Sign in, refresh, log out, and change own password | Yes | Yes | Yes |
| Read and manage own assessments | Yes | Yes | No |
| Read genre settings | Yes | Yes | No |
| Save owner genre settings | Yes | No | No |
| Read and create owner upload records | Yes | No | No |
| List users | No | No | Yes |
| Read centralized audit logs | No | No | Yes |

Administrator accounts must be provisioned through a controlled operational process. Never expose an unauthenticated endpoint that assigns the `admin` role.

## Database design

The active schema is [`database/schema.sql`](../database/schema.sql). It keeps the original database model as its foundation and appends only tables needed by the security and application workflows. [`database/schema_original.sql`](../database/schema_original.sql) is retained as the reference copy of the original design.

### Original foundation tables

| Table | What it stores | How the application uses it |
|---|---|---|
| `user` | One account per row: login name, password hash, email, role, active status, mandatory-password-change state, security-update time, and creation time. The `user_id` value is the identity used by foreign keys. | Authentication looks up the account by `username` or `email`; the `password` column stores the Argon2id hash; `requires_password_change` restricts temporary-password sessions; `role` is re-checked on protected requests. Application roles are lowercase `owner`, `technician`, and `admin`. |
| `genre_preset` | Shared recommended sound values for a genre, including bass, treble, loudness, sharpness, and flatness. `genre_name` is unique so one shared preset cannot be accidentally duplicated. | The analysis result points to a preset through `preset_id`. This preserves which recommendation was used for an assessment. |
| `audio_quality_threshold` | Named quality rules: maximum noise, maximum distortion, and minimum quality score. | An analysis result points to the threshold used through `threshold_id`, making the decision reproducible if thresholds change later. |
| `assessment` | The uploaded-audio job itself: owner (`user_id`), file path, processing status, date, external API reference, processing time, display name, duration, and result status. | This is the parent record for one audio assessment. Its lifecycle is represented by `assessment_status`; application metadata is stored on the same row because it depends directly on `assessment_id`; detailed measurements belong in `audio_analysis_result`. |
| `audio_analysis_result` | The measured output for one assessment: quality score, noise, distortion, recommended sound values, waveform path, and spectrogram path. | `assessment_id` is unique, so one assessment has at most one detailed result. `threshold_id` and `preset_id` document the rules and recommendation used for that result. |

### Additive tables

These tables do not replace the original tables. They add capabilities that the original design did not contain.

| Table | What it stores | Why it is separate |
|---|---|---|
| `refresh_token` | A hash of each long-lived refresh token, its owner, expiry, revocation time, client IP, and user agent. | One user may sign in on multiple devices. A separate row per session supports rotation and logout revocation without storing a bearer token in plaintext. |
| `revoked_access_token` | The JWT `jti`, owner, expiry, and revocation time for access tokens invalidated before natural expiry. | Access tokens are normally stateless. This small denylist allows logout and emergency revocation while retaining short-lived tokens. |
| `audit_log` | Security and accountability events such as login failures, authorization failures, password resets, and data changes, including actor, action, result, client information, and timestamp. | Audit records are append-only events. They should not be columns on `user` or `assessment`, because one actor can create many events across many resource types. |
| `user_genre_setting` | A user's saved genre adjustment, optionally linked to the shared `genre_preset`, including volume and tone values. | Shared presets and user-specific overrides have different ownership and lifecycles, so overrides belong in a child table. |
| `audio_upload` | An upload record with owner, optional assessment, filename, genre label, score, status, and creation time. | An upload may exist before processing creates an `assessment`; the nullable relationship supports that workflow without changing the original assessment table. |

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

Run the backend security regression tests from `backend` with:

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
