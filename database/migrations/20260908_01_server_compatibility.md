# Server compatibility migration

Prepared against the supplied `karaok-server-schema.sql` export and current
`database/schema.sql`. The export has 12 tables; the current bootstrap has 11.
The server is missing `amplifier_profile`, `settings_recommendation`, and the
`audio_analysis_result.quality_profile_version` / `quality_profile_checksum`
columns. The other shared table definitions are compatible, allowing for
MySQL's normalized defaults, implicit indexes, and BOOLEAN representation.

The SQL adds the missing structures and preserves all existing records,
`genre_preset`, `audio_quality_threshold`, `user_genre_setting`, and the old
result foreign keys/columns. Expect 14 tables after this compatibility migration,
not the fresh-install count of 11. Retiring old structures is separate work.

The two new provenance columns are intentionally nullable for historical rows.
The schema-only export cannot establish their original profile identity. New
backend writes supply both fields; existing backend history handling accepts
missing provenance. Do not backfill historical records with the current profile
checksum or make the columns NOT NULL without verified historical provenance.

## Deployment

1. Upload the SQL file to the Ubuntu user's home using SCP.
2. Keep settings recommendations disabled. Stop `karaok-api` and any other
   database writers for the backup and migration window.
3. Create a full database backup with `mysqldump --single-transaction
   --routines --triggers --events --no-tablespaces`; use restrictive permissions,
   verify successful exit and a nonempty backup, and retain it for recovery.
4. Apply once: `sudo mysql --database=karaok_db < ~/20260908_01_server_compatibility.sql`.
   Do not use `--force`. MySQL DDL commits implicitly: if any statement fails,
   inspect the partially applied schema before retrying. Do not blindly rerun.
5. Inspect `SHOW CREATE TABLE` for both new tables and `SHOW COLUMNS FROM
   audio_analysis_result`. Confirm old assessment counts are unchanged.
6. Restart the API and verify internal/public health, existing history, and a
   new quality assessment. Confirm the new result has nonnull profile version
   and checksum. Schema readiness alone does not authorize enabling settings
   recommendations; the separate controlled-trial gate still applies.

## Validation and limitations

The new table definitions are copied exactly from the authoritative bootstrap.
The supplied export was checked for the missing objects and all shared columns.
No DROP, DELETE, UPDATE, or TRUNCATE is included. This migration has not been
executed against MySQL 8 in this workspace; the installed local CLI is MariaDB
10.4. Validate on a disposable MySQL copy before applying to production.
The export does not include live grants; if access is granted per table, grant
the application identity the required rights on the new tables separately.
Do not grant unrestricted administration privileges.

Rollback should keep the added structures and restore the previous application
version if necessary. Database restoration is a separate destructive recovery
operation, not an automatic rollback command.
