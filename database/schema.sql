-- KaraOK consolidated schema
--
-- Authoritative bootstrap for a new empty database. It includes the final
-- structure introduced by all migrations through 2026-07-20. It intentionally
-- does not DROP an existing database and should not be used as a substitute for
-- migrations on a populated deployment.
--
-- Password recovery uses user.requires_password_change and does not require
-- the retired password_reset_token table.

CREATE DATABASE IF NOT EXISTS karaok_db;
USE karaok_db;

-- ==========================================
-- USER
-- ==========================================

CREATE TABLE IF NOT EXISTS user (
    user_id INT AUTO_INCREMENT PRIMARY KEY,

    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    email_verified_at DATETIME NULL,

    -- Kept as a string so roles are extensible; no user-type ENUM is used.
    role VARCHAR(30) NOT NULL DEFAULT 'Consumer',

    -- Merged from the former user_security table.
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    requires_password_change BOOLEAN NOT NULL DEFAULT FALSE,
    security_updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==========================================
-- GENRE PRESET
-- Stores the recommended sound settings
-- ==========================================

CREATE TABLE IF NOT EXISTS genre_preset (
    preset_id INT AUTO_INCREMENT PRIMARY KEY,

    genre_name VARCHAR(50) NOT NULL UNIQUE,

    bass FLOAT NOT NULL,
    treble FLOAT NOT NULL,
    loudness FLOAT NOT NULL,
    sharpness FLOAT NOT NULL,
    flatness FLOAT NOT NULL
);

-- ==========================================
-- AUDIO QUALITY THRESHOLD
-- Stores empirical threshold values
-- ==========================================

CREATE TABLE IF NOT EXISTS audio_quality_threshold (
    threshold_id INT AUTO_INCREMENT PRIMARY KEY,

    threshold_name VARCHAR(100) NOT NULL,

    max_allowable_noise FLOAT NOT NULL,
    max_allowable_distortion FLOAT NOT NULL,
    min_quality_score FLOAT NOT NULL
);

-- ==========================================
-- ASSESSMENT
-- One uploaded audio per assessment
-- ==========================================

CREATE TABLE IF NOT EXISTS assessment (
    assessment_id INT AUTO_INCREMENT PRIMARY KEY,

    user_id INT NOT NULL,

    audio_file_path VARCHAR(255),

    assessment_status ENUM('Pending','Processing','Completed','Failed')
        DEFAULT 'Pending',

    assessment_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    api_reference VARCHAR(100),

    processing_time FLOAT,

    analysis_purpose VARCHAR(40) NOT NULL DEFAULT 'quality_evaluation',

    -- Merged from the former assessment_metadata table.
    test_name VARCHAR(120),
    duration_seconds INT NOT NULL DEFAULT 0,
    result_status VARCHAR(30) NOT NULL DEFAULT 'Acceptable',

    KEY idx_assessment_user_date (user_id, assessment_date),

    CONSTRAINT fk_assessment_user
        FOREIGN KEY (user_id)
        REFERENCES user(user_id)
        ON DELETE CASCADE
);

-- ==========================================
-- AUDIO ANALYSIS RESULT
-- Stores quality assessment and genre recommendation results
-- ==========================================

CREATE TABLE IF NOT EXISTS audio_analysis_result (
    result_id INT AUTO_INCREMENT PRIMARY KEY,

    assessment_id INT NOT NULL UNIQUE,

    threshold_id INT NULL,

    preset_id INT NULL,

    quality_score FLOAT,

    noise_level FLOAT,

    distortion_level FLOAT,

    bass FLOAT,

    treble FLOAT,

    loudness FLOAT,

    sharpness FLOAT,

    flatness FLOAT,

    empirical_status VARCHAR(40),

    worst_feature_status VARCHAR(40),

    worst_features JSON,

    empirical_details JSON,

    scoring_algorithm_version VARCHAR(30),

    reference_recording_count INT,

    waveform_path VARCHAR(255),

    spectrogram_path VARCHAR(255),

    CONSTRAINT fk_result_assessment
        FOREIGN KEY (assessment_id)
        REFERENCES assessment(assessment_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_result_threshold
        FOREIGN KEY (threshold_id)
        REFERENCES audio_quality_threshold(threshold_id),

    CONSTRAINT fk_result_preset
        FOREIGN KEY (preset_id)
        REFERENCES genre_preset(preset_id)
);

-- ==========================================
-- REFRESH TOKEN
-- Stores only hashes of long-lived session tokens.
-- ==========================================

CREATE TABLE IF NOT EXISTS refresh_token (
    refresh_token_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    token_hash CHAR(64) NOT NULL UNIQUE,
    expires_at DATETIME NOT NULL,
    revoked_at DATETIME NULL,
    ip_address VARCHAR(45),
    user_agent VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY idx_refresh_token_user (user_id, revoked_at, expires_at),
    CONSTRAINT fk_refresh_token_user
        FOREIGN KEY (user_id) REFERENCES user(user_id) ON DELETE CASCADE
);

-- ==========================================
-- REVOKED ACCESS TOKEN
-- ==========================================

CREATE TABLE IF NOT EXISTS revoked_access_token (
    jti CHAR(32) PRIMARY KEY,
    user_id INT NOT NULL,
    expires_at DATETIME NOT NULL,
    revoked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_revoked_access_user
        FOREIGN KEY (user_id) REFERENCES user(user_id) ON DELETE CASCADE
);

-- ==========================================
-- AUDIT LOG
-- ==========================================

CREATE TABLE IF NOT EXISTS audit_log (
    audit_log_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NULL,
    action VARCHAR(80) NOT NULL,
    resource_type VARCHAR(80) NULL,
    resource_id BIGINT NULL,
    result VARCHAR(20) NOT NULL,
    ip_address VARCHAR(45) NULL,
    user_agent VARCHAR(255) NULL,
    details VARCHAR(500) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY idx_audit_log_created (created_at),
    CONSTRAINT fk_audit_log_user
        FOREIGN KEY (user_id) REFERENCES user(user_id) ON DELETE SET NULL
);

-- ==========================================
-- USER GENRE SETTINGS
-- Preserves genre_preset as the shared preset foundation while allowing
-- owner-specific saved settings.
-- ==========================================

CREATE TABLE IF NOT EXISTS user_genre_setting (
    setting_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    preset_id INT NULL,
    genre_name VARCHAR(50) NOT NULL,
    volume FLOAT NOT NULL,
    bass FLOAT NOT NULL,
    treble FLOAT NOT NULL,
    flatness FLOAT NOT NULL,
    sharpness FLOAT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_user_genre_setting_user
        FOREIGN KEY (user_id) REFERENCES user(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_user_genre_setting_preset
        FOREIGN KEY (preset_id) REFERENCES genre_preset(preset_id) ON DELETE SET NULL
);

-- ==========================================
-- AUDIO UPLOAD RECORD
-- ==========================================

CREATE TABLE IF NOT EXISTS audio_upload (
    upload_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    assessment_id INT NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    genre_name VARCHAR(50) NULL,
    score FLOAT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'Acceptable',
    size_bytes BIGINT UNSIGNED NULL,
    mime_type VARCHAR(100) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_audio_upload_assessment (assessment_id),
    KEY idx_audio_upload_created (created_at),
    CONSTRAINT fk_audio_upload_assessment
        FOREIGN KEY (assessment_id) REFERENCES assessment(assessment_id) ON DELETE CASCADE
);

-- ==========================================
-- API REQUEST LOG
-- Stores sanitized request metadata only. Bodies, credentials, tokens, OTPs,
-- and uploaded bytes are intentionally excluded.
-- ==========================================

CREATE TABLE IF NOT EXISTS api_request_log (
    request_log_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NULL,
    method VARCHAR(10) NOT NULL,
    path VARCHAR(255) NOT NULL,
    endpoint VARCHAR(100) NULL,
    status_code SMALLINT UNSIGNED NOT NULL,
    duration_ms FLOAT NOT NULL,
    ip_address VARCHAR(45) NULL,
    user_agent VARCHAR(255) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY idx_api_request_log_created (created_at),
    KEY idx_api_request_log_user_created (user_id, created_at),
    CONSTRAINT fk_api_request_log_user
        FOREIGN KEY (user_id) REFERENCES user(user_id) ON DELETE SET NULL
);

-- ==========================================
-- REGISTRATION OTP
-- Connects each pending email code to one unverified user account.
-- ==========================================

CREATE TABLE IF NOT EXISTS registration_otp (
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

-- ==========================================
-- SEED DATA
-- Safe to run repeatedly after the tables exist.
-- ==========================================

INSERT IGNORE INTO genre_preset
    (genre_name, bass, treble, loudness, sharpness, flatness)
VALUES
    ('Ballad', 55, 50, 60, 45, 50),
    ('Pop', 60, 60, 65, 55, 50),
    ('Rock', 70, 65, 70, 60, 45),
    ('Acoustic', 45, 65, 55, 60, 65);

INSERT INTO audio_quality_threshold
    (threshold_name, max_allowable_noise, max_allowable_distortion, min_quality_score)
SELECT 'Default', 10, 5, 60
WHERE NOT EXISTS (
    SELECT 1
      FROM audio_quality_threshold
     WHERE threshold_name = 'Default'
);
