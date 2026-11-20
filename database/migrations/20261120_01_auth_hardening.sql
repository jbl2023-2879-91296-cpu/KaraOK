-- Deploy with the matching KaraOK client. Pending legacy codes are invalidated.
USE karaok_db;

CREATE TABLE IF NOT EXISTS auth_throttle (
    throttle_key CHAR(64) PRIMARY KEY,
    window_started_at DOUBLE NOT NULL,
    hits INT UNSIGNED NOT NULL DEFAULT 0,
    strikes TINYINT UNSIGNED NOT NULL DEFAULT 0,
    locked_until DOUBLE NOT NULL DEFAULT 0,
    last_seen_at DOUBLE NOT NULL,
    KEY idx_auth_throttle_last_seen (last_seen_at)
);

CREATE TABLE IF NOT EXISTS password_reset_otp (
    reset_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    email VARCHAR(254) NOT NULL,
    challenge_id CHAR(32) NOT NULL,
    last_sent_at DATETIME NOT NULL,
    send_count_window_start DATETIME NOT NULL,
    send_count TINYINT UNSIGNED NOT NULL DEFAULT 0,
    code_hash CHAR(64) NOT NULL,
    expires_at DATETIME NOT NULL,
    attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_password_reset_otp_challenge (challenge_id),
    UNIQUE KEY uq_password_reset_otp_user (user_id),
    KEY idx_password_reset_otp_expires (expires_at),
    CONSTRAINT fk_password_reset_otp_user
        FOREIGN KEY (user_id) REFERENCES user(user_id) ON DELETE CASCADE
);

DELETE FROM registration_otp WHERE code_hash IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'registration_otp' AND column_name = 'challenge_id'
);

SET @auth_ddl = IF(
    EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema = DATABASE() AND table_name = 'registration_otp' AND column_name = 'email'),
    'SELECT 1', 'ALTER TABLE registration_otp ADD COLUMN email VARCHAR(254) NOT NULL'
);
PREPARE auth_migration FROM @auth_ddl;
EXECUTE auth_migration;
DEALLOCATE PREPARE auth_migration;

SET @auth_ddl = IF(
    EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema = DATABASE() AND table_name = 'registration_otp' AND column_name = 'challenge_id'),
    'SELECT 1', 'ALTER TABLE registration_otp ADD COLUMN challenge_id CHAR(32) NOT NULL'
);
PREPARE auth_migration FROM @auth_ddl;
EXECUTE auth_migration;
DEALLOCATE PREPARE auth_migration;

SET @auth_ddl = IF(
    EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema = DATABASE() AND table_name = 'registration_otp' AND column_name = 'last_sent_at'),
    'SELECT 1', 'ALTER TABLE registration_otp ADD COLUMN last_sent_at DATETIME NOT NULL'
);
PREPARE auth_migration FROM @auth_ddl;
EXECUTE auth_migration;
DEALLOCATE PREPARE auth_migration;

SET @auth_ddl = IF(
    EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema = DATABASE() AND table_name = 'registration_otp' AND column_name = 'send_count_window_start'),
    'SELECT 1', 'ALTER TABLE registration_otp ADD COLUMN send_count_window_start DATETIME NOT NULL'
);
PREPARE auth_migration FROM @auth_ddl;
EXECUTE auth_migration;
DEALLOCATE PREPARE auth_migration;

SET @auth_ddl = IF(
    EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema = DATABASE() AND table_name = 'registration_otp' AND column_name = 'send_count'),
    'SELECT 1', 'ALTER TABLE registration_otp ADD COLUMN send_count TINYINT UNSIGNED NOT NULL DEFAULT 0'
);
PREPARE auth_migration FROM @auth_ddl;
EXECUTE auth_migration;
DEALLOCATE PREPARE auth_migration;

SET @auth_ddl = IF(
    EXISTS (SELECT 1 FROM information_schema.statistics
            WHERE table_schema = DATABASE() AND table_name = 'registration_otp' AND index_name = 'uq_registration_otp_challenge'),
    'SELECT 1', 'ALTER TABLE registration_otp ADD UNIQUE INDEX uq_registration_otp_challenge (challenge_id)'
);
PREPARE auth_migration FROM @auth_ddl;
EXECUTE auth_migration;
DEALLOCATE PREPARE auth_migration;

SET @auth_ddl = IF(
    EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema = DATABASE() AND table_name = 'user' AND column_name = 'email_canonical'),
    'SELECT 1', 'ALTER TABLE user ADD COLUMN email_canonical VARCHAR(254) NULL'
);
PREPARE auth_migration FROM @auth_ddl;
EXECUTE auth_migration;
DEALLOCATE PREPARE auth_migration;

SET @auth_ddl = IF(
    EXISTS (SELECT 1 FROM information_schema.statistics
            WHERE table_schema = DATABASE() AND table_name = 'user' AND index_name = 'idx_user_email_canonical'),
    'SELECT 1', 'ALTER TABLE user ADD INDEX idx_user_email_canonical (email_canonical)'
);
PREPARE auth_migration FROM @auth_ddl;
EXECUTE auth_migration;
DEALLOCATE PREPARE auth_migration;

-- Profile edits must not invalidate other devices. Password changes explicitly bump this value.
SET @auth_ddl = IF(
    EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema = DATABASE() AND table_name = 'user'
              AND column_name = 'security_updated_at'
              AND (datetime_precision <> 6 OR LOWER(extra) LIKE '%on update%')),
    'ALTER TABLE user MODIFY security_updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6)',
    'SELECT 1'
);
PREPARE auth_migration FROM @auth_ddl;
EXECUTE auth_migration;
DEALLOCATE PREPARE auth_migration;

UPDATE user
SET email_canonical = CONCAT(
    CASE WHEN SUBSTRING_INDEX(LOWER(email), '@', -1) IN ('gmail.com', 'googlemail.com')
         THEN REPLACE(SUBSTRING_INDEX(SUBSTRING_INDEX(LOWER(email), '@', 1), '+', 1), '.', '')
         ELSE SUBSTRING_INDEX(SUBSTRING_INDEX(LOWER(email), '@', 1), '+', 1)
    END, '@',
    CASE WHEN SUBSTRING_INDEX(LOWER(email), '@', -1) = 'googlemail.com' THEN 'gmail.com'
         ELSE SUBSTRING_INDEX(LOWER(email), '@', -1)
    END
)
WHERE email_canonical IS NULL;
