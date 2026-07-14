# Changelog

All notable changes to KaraOK are documented here.

## 2026-07-14 — Security and operational database foundation

### Added

- Environment-based backend configuration through `backend/.env` and `.env.example`.
- Argon2id password hashing with per-password salts.
- JWT access tokens with expiry and revoked-token tracking.
- Rotating, hashed refresh tokens with logout revocation.
- Password reset tokens that are hashed, single-use, and time-limited.
- Authentication rate limiting, input validation, security headers, and audit logging.
- Server-side role-based access control for owner and technician routes.
- Flutter secure storage for access and refresh tokens, automatic access-token refresh, and API URL overrides.
- An API-aligned schema for users, sessions, password resets, audio records, and audit logs.
- `database/schema_original.sql` retained as the original project schema for comparison.

### Changed

- Replaced the original `user`/`assessment`-oriented schema with tables that directly support the implemented API and security workflows.
- Changed API ownership decisions to use authenticated token identity instead of trusting a client-supplied `user_id`.
- Added constraints and indexes for valid score/settings ranges, unique emails/tokens, foreign keys, and common history queries.

### Notes

- `schema.sql` must be imported into the target MySQL database; `CREATE TABLE IF NOT EXISTS` does not migrate existing tables automatically.
- The active schema is normalized for the current feature set. Repeated values in historical rows are intentional snapshots so past reports remain auditable.
- Real audio capture and signal analysis remain future work; the current UI can persist simulated result data.

## 2026-07-15 — Normalized one-to-one table merges

### Changed

- Merged `user_security` into `user` because account security state is one-to-one with `user_id`.
- Merged `assessment_metadata` into `assessment` because test name, duration, and result status depend directly on `assessment_id`.
- Removed those two standalone tables from `schema.sql` while preserving all other additive security, audit, preset, and upload tables.

### Documentation

- Updated the backend README table descriptions, relationships, and normalization explanation to document the merged design.
