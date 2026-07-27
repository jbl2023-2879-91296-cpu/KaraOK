# KaraOK Database

`schema.sql` is the authoritative v2 bootstrap for a new empty KaraOK database
as of 2026-07-27. This release uses a deliberate fresh-database deployment:
back up the existing database, recreate `karaok_db`, and import this file. No
migration file is required afterward. The script itself does not drop an
existing database.

The v2 `user` table removes the public owner/technician account types. Public
registration always creates the internal role `user`; `admin` remains available
only for accounts provisioned outside public registration. Authentication
accepts either the unique username or verified email address.

Each user stores required `username`, `first_name`, `last_name`, street
`address`, `city`, `state_province`, `area_code`, `country`, two-letter ISO
`country_code`, unique `phone_number`, and `birthday` values.
The optional `profile_image` and `profile_image_mime` columns store a validated
JPEG, PNG, or WebP image of at most 2 MB. Keeping optional image bytes on the
account row ensures account deletion does not leave an orphaned profile file.

`schema_original.sql` is retained only as a reference for the original design.
`Audio_Analysis_db.mwb` is the MySQL Workbench model and should reflect the
active schema.

## Why user relationships store `user_id` on the child table

The `user` row represents one permanent account. Security sessions, logs, and
requests are separate records that occur repeatedly during that account's
lifetime. Their foreign key therefore belongs on the child, or "many", side:

```text
user
|--< audit_log
|--< refresh_token
|--< api_request_log
|--< revoked_access_token
`--- 0..1 registration_otp
```

| Relationship | Cardinality | Reason |
| --- | --- | --- |
| `user` to `audit_log` | One-to-many | Every login, password recovery, upload, authorization failure, and data change may create another audit event. Keeping separate rows preserves the complete event history. |
| `user` to `refresh_token` | One-to-many | One account can have simultaneous sessions on a phone, browser, and other devices. Each refresh token has its own hash, expiry, revocation state, IP address, and user agent. |
| `user` to `api_request_log` | One-to-many | Every API operation creates a separate request record. `api_request_log.user_id` is nullable because unauthenticated requests have no known user. |
| `user` to `revoked_access_token` | One-to-many | A user can have multiple access tokens revoked over the lifetime of the account. Each JWT identifier and expiry must remain independently queryable. |
| `user` to `registration_otp` | One-to-zero-or-one | OTP state is temporary and is removed after successful verification. `UNIQUE KEY uq_registration_otp_user (user_id)` ensures that a user can have at most one pending OTP. |

Placing child IDs such as `refresh_token_id` or `audit_log_id` on `user` would
provide only one slot for each type of record. A later login, request, or audit
event would overwrite the previous ID and make its history unreachable.
Adding repeated columns such as `refresh_token_id_1`, `refresh_token_id_2`, or
storing ID arrays would also prevent normal foreign-key enforcement and make
indexing and querying harder.

With `user_id` on each child row, any number of related records can reference
the same account:

```text
refresh_token_id  user_id
----------------  -------
101               7
102               7
103               7
```

This direction also allows MySQL to enforce ownership and apply the configured
`ON DELETE CASCADE` or `ON DELETE SET NULL` behavior consistently.

## Why registration OTP remains separate

Registration OTP fields are short-lived security state rather than permanent
account attributes. A separate table allows the application to replace an
expired code, increment its attempt count, and delete it after verification
without adding temporary fields to every established account. The unique
`user_id` constraint gives it the intended zero-or-one relationship while
preserving a clean lifecycle boundary.

Passwords and OTPs are never stored in plaintext. `user.password` contains an
Argon2id hash, while `registration_otp.code_hash` contains a one-way code hash.
The current password-recovery workflow uses
`user.requires_password_change`; it does not require the retired
`password_reset_token` table.

## Assessment and upload ownership

`assessment.user_id` is the single source of ownership for an evaluation.
`audio_upload` references one assessment through a non-null unique
`assessment_id`, producing a one-to-zero-or-one relationship from assessment to
upload. The upload does not repeat `user_id`; its owner is obtained by joining
through assessment:

```sql
SELECT au.*
FROM audio_upload AS au
JOIN assessment AS a ON a.assessment_id = au.assessment_id
WHERE a.user_id = ?;
```

This removes the possibility that an assessment names one user while its upload
names another. Deleting an assessment cascades to its upload metadata because
that metadata has no independent owner or analysis lifecycle.

The uploaded audio itself is request-scoped, so `assessment` does not store an
`audio_file_path`. After a completed analysis, `audio_analysis_result` stores
relative `waveform_path` and `spectrogram_path` values for the two Matplotlib
PNGs used by the detailed report. The API resolves them inside the configured
analysis-output root and verifies assessment ownership before serving a file.
