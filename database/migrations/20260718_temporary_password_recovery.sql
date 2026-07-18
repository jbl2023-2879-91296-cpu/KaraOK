USE karaok_db;

-- Run once before deploying the temporary-password recovery backend.
ALTER TABLE user
    ADD COLUMN requires_password_change BOOLEAN NOT NULL DEFAULT FALSE
    AFTER is_active;
