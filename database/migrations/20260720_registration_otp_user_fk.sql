USE karaok_db;

-- Run once before deploying the registration-OTP user-link backend.
-- Existing accounts predate this column and are therefore already verified.
ALTER TABLE user
    ADD COLUMN email_verified_at DATETIME NULL
    AFTER email;

UPDATE user
SET email_verified_at = COALESCE(created_at, UTC_TIMESTAMP())
WHERE email_verified_at IS NULL;

-- Pending OTPs are short-lived and cannot reference a user in the old model.
-- Recreating this table invalidates only unfinished registrations; those users
-- must submit registration again to receive a new code.
DROP TABLE registration_otp;

CREATE TABLE registration_otp (
    registration_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    code_hash CHAR(64) NOT NULL,
    expires_at DATETIME NOT NULL,
    attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_registration_otp_user (user_id),
    CONSTRAINT fk_registration_otp_user
        FOREIGN KEY (user_id) REFERENCES user(user_id) ON DELETE CASCADE
);
