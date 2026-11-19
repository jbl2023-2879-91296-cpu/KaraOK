# Simplified signup and deferred profile completion

Signup requires only email, username and password. Email code verification is
still required before authentication; existing password, role, OTP expiry,
attempt limits, rate limits and token behavior remain in place. Older clients
may send personal fields at signup; supplied values retain their validation.
Missing details are SQL NULL, including phone and birthday. The unique phone
index remains: multiple NULLs are allowed, duplicate supplied phones are not.

After verification/login, Home offers **Complete profile** and **Not now**.
Completion opens the existing Account editor. Skipping does not restrict app
features; Account > Edit remains available. Saving the complete profile keeps
existing validation, immutable email and username/phone uniqueness. Photos are
optional and do not affect completion. API user responses include
`profile_complete`; the Flutter session also derives completion from the fields.

## Existing database rollout

Back up the database and apply
`database/migrations/20261017_01_deferred_profile.sql` **before** deploying the
backend. Run it with a database account permitted to ALTER the user table. It
targets `karaok_db`; change USE if your deployment uses a different database.
The ALTER only makes ten personal columns nullable, preserves existing data and
unique indexes, and can be rerun. MySQL ALTER TABLE may lock/rebuild the table;
choose an appropriate maintenance window. It does not fabricate or rewrite any
profile values. Fresh installs use `database/schema.sql` instead.

Local status (2026-10-17): applied by the coordinating developer to
`localhost/karaok_db`; all ten personal columns were verified nullable and the
account count was unchanged. The prior user-table DDL snapshot is saved at
`%TEMP%/karaok-user-schema-before-deferred-profile.sql`. No external database was
touched. Remote/staging/production deployments still require the migration
before deploying the backend.

Reverting to NOT NULL after
minimal signups requires collecting missing details first; do not fill them with
placeholder data. Database backup/restore is the rollback option if required.

Focused checks: `python -m unittest tests.test_deferred_profile tests.test_security`
from backend, and `flutter test --no-pub test/deferred_profile_test.dart test/widget_test.dart`
from frontend. Backend tests mock database access; validate the ALTER against a
staging copy of the deployed MySQL database before rollout.
