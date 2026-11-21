# KaraOK Database

`schema.sql` is the authoritative MySQL fresh-install schema for KaraOK. It
creates the database, 13 tables, foreign keys, and indexes. Versioned JSON
artifacts provide quality thresholds, genre profiles, and control priors.

## Important installation rule

The schema is intended for a new or empty `karaok_db`. It uses
`CREATE TABLE IF NOT EXISTS` and does not migrate an older populated schema.
Back up existing data before rebuilding or applying manual alterations.

## Import

```powershell
mysql -u root -p --execute="source database/schema.sql"
```

To verify the import:

```sql
USE karaok_db;
SHOW TABLES;
SHOW CREATE TABLE amplifier_profile;
SHOW CREATE TABLE settings_recommendation;
```

## Tables

| Table | Purpose |
| --- | --- |
| `user` | Login identity, required profile, optional image, and account state |
| `registration_otp` | One pending hashed email-verification code per user |
| `password_reset_otp` | One pending email-bound password reset challenge per user |
| `auth_throttle` | Worker-shared auth attempt windows, lockouts, and OTP send limits |
| `refresh_token` | Hashed renewable sessions and revocation time |
| `revoked_access_token` | Explicitly revoked JWT identifiers |
| `assessment` | User-owned evaluation lifecycle and summary metadata |
| `audio_analysis_result` | Measurements, empirical grading, and visualization paths |
| `audio_upload` | Original filename, type, size, genre, score, and status metadata |
| `audit_log` | Security and business audit events |
| `api_request_log` | Sanitized request metadata without bodies or credentials |
| `amplifier_profile` | User-owned physical amplifier scale and control positions |
| `settings_recommendation` | Five-control recommendations and verification linkage |

## Account model

Public registration creates only the `user` role. The `admin` role remains for
internal provisioning. Sign-up needs only a verified email and a password; the
account then exists with an empty profile.

- unique username and verified email are required at sign-up
- first and last name, address fields, country, phone number and birthday are
  nullable and are completed later from Settings (the app prompts once)
- optional profile image up to 5 MB in JPEG, PNG, WebP, GIF, HEIC/HEIF, AVIF,
  or BMP format

User-chosen passwords are 8 to 128 characters; generated temporary passwords are
exactly eight. Both need uppercase, lowercase, number, and symbol characters.
The database stores only Argon2id hashes. OTP codes and refresh tokens are also
stored only as one-way hashes.

## Assessment ownership

`assessment.user_id` is the source of ownership. `audio_upload` and
`audio_analysis_result` each reference an assessment rather than repeating a
user ID. Deleting an assessment cascades to its dependent business rows.

Uploaded audio is request-scoped and is not stored in the database. The removed
`assessment.audio_file_path` column must not be reintroduced. Completed signed-
in analyses store relative `waveform_path` and `spectrogram_path` values; the
API resolves them inside configured storage after verifying ownership.

Guest assessments are not database records. Their metadata and report images
remain in app-private device storage and are not imported, claimed, or assigned
when the guest later creates an account or signs in.

The mobile client can keep an app-private, per-user cache of history metadata
and downloaded visualization bytes. That cache is not part of the relational
model: MySQL remains authoritative, ownership is rechecked whenever the server
is contacted, and server-side assessment deletion cascades through its business
rows.

## Calibration artifacts

Quality thresholds, genre targets, and starting controls live in versioned JSON
artifacts under `backend/audio_thresholds/`. The retired lookup tables and result
foreign keys are absent from the fresh schema. See [profile sources](../docs/design/settings-profile-sources.md).

## Nullable fields

Several null values are intentional:

- profile image fields are null when a user does not upload an image
- `genre_name` is null when no genre is selected
- `revoked_at` is null for an active refresh token
- audit user/resource fields are null for public or non-resource events
- request `endpoint` may be null for an unmatched route

## Production operations

- Use a dedicated least-privilege MySQL user for the API.
- Use a separate `karaok_admin_api` identity for the Data Administration API.
  Grant only the SELECT/SHOW VIEW access and table/column CRUD permissions
  implemented by its policy; do not grant schema privileges.
- The administration feature adds no table or column and does not require a
  schema rebuild.
- Encrypt database backups and restrict their filesystem permissions.
- Back up MySQL and saved analysis images on a coordinated schedule.
- Test restoration regularly.
- Never store database credentials in this public README or in `schema.sql`.

## Migrations for an existing database

`schema.sql` already contains every column below, so a fresh install needs
none of these. A populated database must have them applied, in order, before the
matching backend is deployed. Each file is safe to run more than once.

| File | Adds | Needed by |
| --- | --- | --- |
| `migrations/20261017_01_deferred_profile.sql` | Nullable profile fields on `user` | Email-only sign-up |
| `migrations/20261025_01_recommendation_feedback.sql` | `settings_recommendation.feedback` | Listener feedback on suggestions |
| `migrations/20261025_02_noise_reliable.sql` | `audio_analysis_result.noise_reliable` | Noise reliability labels |
| `migrations/20261118_01_noise_guard.sql` | Noise Guard columns on `audio_analysis_result` (`noise_guard_usable_pct`, `noise_guard_confidence`, `preroll_noise_dbfs`) | Noise check before recording |
| `migrations/20261119_01_flatness_reliability.sql` | `audio_analysis_result.flatness_reliable`, `flatness_reliability_note` | Flatness reliability labels |
| `migrations/20261119_02_retention_indexes.sql` | Date and expiry indexes on `user`, `assessment`, `settings_recommendation` and the token tables | Fast admin reports and the nightly retention cleanup (optional, no column changes) |
| `migrations/20261120_01_auth_hardening.sql` | Auth throttle, email-bound OTPs, canonical email and explicit password security timestamps | Coordinated API and mobile auth upgrade |

```bash
sudo mysql < database/migrations/20261017_01_deferred_profile.sql
sudo mysql < database/migrations/20261025_01_recommendation_feedback.sql
sudo mysql < database/migrations/20261025_02_noise_reliable.sql
sudo mysql < database/migrations/20261118_01_noise_guard.sql
sudo mysql < database/migrations/20261119_01_flatness_reliability.sql
sudo mysql < database/migrations/20261119_02_retention_indexes.sql
sudo mysql < database/migrations/20261120_01_auth_hardening.sql
```

The backend health check (`/api/health`) returns HTTP 503 with
`"schema": "missing_required_columns"` when a required column is absent, so a
skipped migration shows up immediately after a restart.

## Existing server compatibility

See [the compatibility migration](migrations/20260908_01_server_compatibility.md)
for the specific legacy server schema. It preserves retired structures and
expects 14 tables in the historical schema. Validate against a
disposable MySQL copy before use; it is not a generic or repeatable migration.

## Retention cleanup

`backend/scripts/purge_old_records.py` keeps the fast-growing tables bounded. It
deletes in batches of 5,000 rows, and it never touches users, assessments,
scores or analysis details.

| Data | Kept for | Setting in `backend/.env` |
| --- | --- | --- |
| `api_request_log` rows | 90 days | `REQUEST_LOG_RETENTION_DAYS` |
| `audit_log` rows | 365 days | `AUDIT_LOG_RETENTION_DAYS` |
| Waveform and spectrogram PNGs (~1.1 MB per recording) | forever | `VISUALIZATION_RETENTION_DAYS` (0 = keep) |
| Expired `refresh_token`, `revoked_access_token`, `registration_otp`, `password_reset_otp` | 1 day after expiry | always on |
| `auth_throttle` | 1 day after the last activity | always on |

Set any window to `0` to keep that data forever. When images are removed, their
paths are cleared and the report shows "Visualization is unavailable" for that
recording; the score and details remain.

Server install (runs daily at 04:00, after the 03:15 backup):

```bash
cd /opt/karaok/app/backend && sudo -u karaok .venv/bin/python scripts/purge_old_records.py --dry-run
sudo install -m 0644 deploy/ovh/karaok-retention.service deploy/ovh/karaok-retention.timer /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now karaok-retention.timer
```

The app's MySQL user needs `DELETE` on `api_request_log`, `audit_log`,
`refresh_token`, `revoked_access_token`, `registration_otp`,
`password_reset_otp` and `auth_throttle`, and `UPDATE` on
`audio_analysis_result` (check with `SHOW GRANTS`). Admin queries should filter
on the flat result columns (`quality_score`, `noise_level`, ...) rather than
`JSON_EXTRACT` on `empirical_details`, which cannot use an index.
