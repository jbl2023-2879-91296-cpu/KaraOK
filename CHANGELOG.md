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

## 2026-07-15 — Email-verified registration

### Added

- Added `registration_otp` for pending registrations, hashed six-digit codes, expiration, and verification state.
- Added SMTP environment configuration for real OTP delivery.
- Added repeatable seed records for baseline genre presets and audio-quality thresholds.
- Added `/api/auth/register/verify` and a Flutter OTP entry step.

### Changed

- Changed the registration field label from `Full Name` to `Username`.
- Made the visible registration flow role-neutral while retaining backend roles for authorization.
- Documented SMTP setup, OTP flow, and seed behavior in the README files.

### Compatibility note

- The OTP implementation currently follows the backend's existing application-user table contract. A fresh database created solely from the original-foundation schema requires the backend authentication queries to be migrated to those original table names before the full registration/login flow can operate.

## 2026-07-15 — Flexible login and dedicated OTP screen

### Added

- Added a dedicated email-verification screen for entering the six-digit registration OTP.

### Changed

- Login now accepts either the account username or email address.
- Registration now opens the OTP screen after successfully sending the verification code instead of adding an OTP field to the registration form.
- Connected pending OTP registrations to account creation through a transactional promotion into `user` with a five-attempt verification limit.
- Updated the backend and Flutter README files to document the revised login and registration flows.

## 2026-07-16 — Temporary-password recovery

### Added

- Added SMTP delivery of randomly generated temporary passwords.
- Added an authenticated in-app change-password screen with current-password verification and confirmation.
- Added Change Password above Logout in owner and technician account menus.

### Changed

- Forgot password now returns to login with the requested email prefilled after showing a sent notification.
- Signing in with a temporary password immediately requires the user to choose a permanent password.
- The forced temporary-password replacement asks only for the new password and confirmation; manual changes from the account menu still require the current password.
- Protected API operations are blocked until a user who signed in with a temporary password completes the required password change.
- Password recovery and password changes revoke existing refresh sessions.
- Kept account lookup responses indistinguishable.

### Removed

- Removed the reset-token browser page, reset-link email flow, and mobile reset-token handling in favor of emailed temporary passwords.
