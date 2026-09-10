# KaraOK Database

`schema.sql` is the authoritative MySQL fresh-install schema for KaraOK. It
creates the database, 11 tables, foreign keys, and indexes. Versioned JSON
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
internal provisioning. A user profile requires:

- unique username and verified email
- first and last name
- street, city, province/state, postal/area code, and country
- derived two-letter country code
- unique phone number and birthday
- optional profile image up to 5 MB in JPEG, PNG, WebP, GIF, HEIC/HEIF, AVIF,
  or BMP format

New and temporary passwords are validated by the application as exactly eight
characters with uppercase, lowercase, number, and symbol characters. The
database stores only their Argon2id hashes. OTP codes and refresh tokens are
also stored only as one-way hashes.

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
foreign keys are absent from the fresh schema. See [profile sources](../docs/settings-profile-sources.md).

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

## Existing server compatibility

See [the compatibility migration](migrations/20260908_01_server_compatibility.md)
for the specific legacy server schema. It preserves retired structures and
expects 14 tables, unlike the 11-table fresh install. Validate against a
disposable MySQL copy before use; it is not a generic or repeatable migration.
