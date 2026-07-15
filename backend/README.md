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

## Security model

- Passwords are hashed with Argon2id using per-password salts.
- Access tokens expire after 15 minutes by default.
- Opaque refresh tokens are hashed in MySQL, rotated on use, and expire after seven days by default.
- Logout immediately denylists the access token and revokes the refresh token.
- Password reset uses hashed, single-use, expiring tokens and revokes existing refresh sessions.
- Protected routes derive identity from the access token instead of trusting client-provided user IDs.
- Owner/technician permissions are enforced at each API route.
- Authentication endpoints are rate limited, and sensitive responses use `Cache-Control: no-store`.
- Authentication, authorization failures, password recovery, and data changes are recorded in `audit_logs`.
- Login accepts either the account username or verified email address through the `identifier` field.
- Registration uses a six-digit, expiring OTP. The code is emailed through the configured SMTP provider and only its hash is stored in `registration_otp`.

## Database design

The active schema is [`database/schema.sql`](../database/schema.sql). It keeps the original database model as its foundation and appends only tables needed by the security and application workflows. [`database/schema_original.sql`](../database/schema_original.sql) is retained as the reference copy of the original design.

### Original foundation tables

| Table | What it stores | How the application uses it |
|---|---|---|
| `user` | One account per row: login name, password hash, email, role, active status, security-update time, and creation time. The `user_id` value is the identity used by foreign keys. | Authentication looks up the account by `username` or `email`; the `password` column stores the Argon2id hash; `role` is read by authorization code. `Consumer` is the current owner-facing role label and `Technician` is the technician-facing role label. Account security state is stored here because it is one-to-one with the account. |
| `genre_preset` | Shared recommended sound values for a genre, including bass, treble, loudness, sharpness, and flatness. `genre_name` is unique so one shared preset cannot be accidentally duplicated. | The analysis result points to a preset through `preset_id`. This preserves which recommendation was used for an assessment. |
| `audio_quality_threshold` | Named quality rules: maximum noise, maximum distortion, and minimum quality score. | An analysis result points to the threshold used through `threshold_id`, making the decision reproducible if thresholds change later. |
| `assessment` | The uploaded-audio job itself: owner (`user_id`), file path, processing status, date, external API reference, processing time, display name, duration, and result status. | This is the parent record for one audio assessment. Its lifecycle is represented by `assessment_status`; application metadata is stored on the same row because it depends directly on `assessment_id`; detailed measurements belong in `audio_analysis_result`. |
| `audio_analysis_result` | The measured output for one assessment: quality score, noise, distortion, recommended sound values, waveform path, and spectrogram path. | `assessment_id` is unique, so one assessment has at most one detailed result. `threshold_id` and `preset_id` document the rules and recommendation used for that result. |

### Additive tables

These tables do not replace the original tables. They add capabilities that the original design did not contain.

| Table | What it stores | Why it is separate |
|---|---|---|
| `refresh_token` | A hash of each long-lived refresh token, its owner, expiry, revocation time, client IP, and user agent. | One user may sign in on multiple devices. A separate row per session supports rotation and logout revocation without storing a bearer token in plaintext. |
| `password_reset_token` | A hash of a one-time reset token, its owner, expiry, usage time, and creation time. | Reset requests have their own expiry and one-use lifecycle. Storing them on `user` would overwrite or mix account data with temporary workflow data. |
| `revoked_access_token` | The JWT `jti`, owner, expiry, and revocation time for access tokens invalidated before natural expiry. | Access tokens are normally stateless. This small denylist allows logout and emergency revocation while retaining short-lived tokens. |
| `audit_log` | Security and accountability events such as login failures, authorization failures, password resets, and data changes, including actor, action, result, client information, and timestamp. | Audit records are append-only events. They should not be columns on `user` or `assessment`, because one actor can create many events across many resource types. |
| `user_genre_setting` | A user's saved genre adjustment, optionally linked to the shared `genre_preset`, including volume and tone values. | Shared presets and user-specific overrides have different ownership and lifecycles, so overrides belong in a child table. |
| `audio_upload` | An upload record with owner, optional assessment, filename, genre label, score, status, and creation time. | An upload may exist before processing creates an `assessment`; the nullable relationship supports that workflow without changing the original assessment table. |

### Relationships and normalization

The schema uses `user.user_id` as the account key. `assessment.user_id`, security tables, and upload records reference it with foreign keys. `audio_analysis_result` references `assessment`, `audio_quality_threshold`, and `genre_preset`, while upload records reference `assessment` when applicable. Account security state and assessment application metadata are stored directly on their one-to-one parent rows.

The design is approximately in third normal form: each table describes one subject or event, non-key attributes depend on that table's key, and cross-table relationships are represented by foreign keys. `user_security` and `assessment_metadata` were merged because their columns depended directly and exclusively on `user_id` and `assessment_id`, respectively. Historical measurements such as `quality_score`, `noise_level`, and `bass` intentionally remain on `audio_analysis_result`; they are snapshots of a completed assessment and must not change when a newer preset or threshold is created. That is controlled historical duplication, not an accidental normalization violation.

The role column is a `VARCHAR`, not an enum, so new role labels can be introduced without changing the table definition. The application currently interprets `Consumer` as the owner-facing role and `Technician` as the technician-facing role.

`CREATE DATABASE` and `CREATE TABLE` statements are initialization statements, not migrations. Back up existing data before applying this file to an existing database, and add future changes through explicit migration scripts.

For a local classroom demonstration, `EXPOSE_RESET_TOKEN=true` returns the reset token to the client. Set it to `false` in production and deliver the token through an email provider.

## Endpoints

Public endpoints:

- `GET /api/health`
- `POST /api/auth/register`
- `POST /api/auth/login`
- `POST /api/auth/refresh`
- `POST /api/auth/logout`
- `POST /api/auth/forgot-password`
- `POST /api/auth/reset-password`

`POST /api/auth/login` accepts an `identifier` containing either the username or email address, together with `password`.

Authenticated endpoints:

- `GET /api/users` — owner only
- `GET|POST /api/audio-tests` — owner or technician, scoped to the authenticated user
- `GET|DELETE /api/audio-tests/<id>` — owner or technician, ownership enforced
- `GET /api/genre-settings` — owner or technician
- `POST /api/genre-settings` — owner only
- `GET|POST /api/audio-uploads` — owner only, scoped to the authenticated user
- `GET /api/audit-logs` — owner only

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
