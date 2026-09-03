-- KaraOK fresh-install schema v3
--
-- Authoritative bootstrap for a new empty database as of 2026-09-03. This
-- consolidates all schema changes through the adjusted-settings feature,
-- including amplifier profiles and generated recommendations. Import this file
-- into a new/empty karaok_db; it intentionally does not destroy an existing
-- populated deployment.
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
    first_name VARCHAR(80) NOT NULL,
    last_name VARCHAR(80) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email_verified_at DATETIME NULL,

    address VARCHAR(255) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state_province VARCHAR(100) NOT NULL,
    area_code VARCHAR(20) NOT NULL,
    country VARCHAR(80) NOT NULL,
    country_code CHAR(2) NOT NULL,
    phone_number VARCHAR(20) NOT NULL UNIQUE,
    birthday DATE NOT NULL,

    -- Optional image bytes are kept with the user so deletion cascades do not
    -- leave profile files behind. Registration accepts JPEG, PNG, and WebP.
    profile_image MEDIUMBLOB NULL,
    profile_image_mime VARCHAR(30) NULL,

    -- Every public registration is a user. Admin is internal-only and cannot
    -- be selected by the account-creation API or Flutter UI.
    role ENUM('user', 'admin') NOT NULL DEFAULT 'user',

    -- Merged from the former user_security table.
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    requires_password_change BOOLEAN NOT NULL DEFAULT FALSE,
    security_updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==========================================
-- ASSESSMENT
-- One uploaded audio per assessment
-- ==========================================

CREATE TABLE IF NOT EXISTS assessment (
    assessment_id INT AUTO_INCREMENT PRIMARY KEY,

    user_id INT NOT NULL,

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

    quality_profile_version VARCHAR(30) NOT NULL,

    quality_profile_checksum CHAR(64) NOT NULL,

    reference_recording_count INT,

    waveform_path VARCHAR(255),

    spectrogram_path VARCHAR(255),

    CONSTRAINT fk_result_assessment
        FOREIGN KEY (assessment_id)
        REFERENCES assessment(assessment_id)
        ON DELETE CASCADE
);

-- ==========================================
-- AMPLIFIER PROFILE
-- Stores owner-scoped physical scale and last-applied knob positions.
-- ==========================================

CREATE TABLE IF NOT EXISTS amplifier_profile (
    amplifier_profile_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    name VARCHAR(80) NOT NULL,
    scale_min DECIMAL(10,3) NOT NULL,
    scale_max DECIMAL(10,3) NOT NULL,
    scale_step DECIMAL(10,3) NOT NULL,
    last_positions JSON NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_amplifier_profile_user_name (user_id, name),
    KEY idx_amplifier_profile_user (user_id),
    CONSTRAINT fk_amplifier_profile_user
        FOREIGN KEY (user_id) REFERENCES user(user_id) ON DELETE CASCADE,
    CONSTRAINT chk_amplifier_profile_scale
        CHECK (scale_min < scale_max AND scale_step > 0)
);

-- ==========================================
-- SETTINGS RECOMMENDATION
-- Persists one generated result per assessment and at most one verification
-- child per recommendation.
-- ==========================================

CREATE TABLE IF NOT EXISTS settings_recommendation (
    recommendation_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    assessment_id INT NOT NULL,
    amplifier_profile_id BIGINT NOT NULL,
    parent_recommendation_id BIGINT NULL,
    genre VARCHAR(50) NOT NULL,
    current_positions JSON NOT NULL,
    recommended_positions JSON NOT NULL,
    adjustments JSON NOT NULL,
    original_score FLOAT NOT NULL,
    verification_score FLOAT NULL,
    overall_confidence VARCHAR(20) NOT NULL,
    algorithm_version VARCHAR(30) NOT NULL,
    scale_min DECIMAL(10,3) NOT NULL,
    scale_max DECIMAL(10,3) NOT NULL,
    scale_step DECIMAL(10,3) NOT NULL,
    genre_profile_version VARCHAR(30) NULL,
    genre_profile_checksum CHAR(64) NULL,
    unavailable_message VARCHAR(255) NULL,
    recommendation_status
        ENUM('generated','applied','verified','reverted','unavailable')
        NOT NULL DEFAULT 'generated',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    applied_at TIMESTAMP NULL,
    UNIQUE KEY uq_settings_recommendation_assessment (assessment_id),
    UNIQUE KEY uq_settings_recommendation_parent (parent_recommendation_id),
    KEY idx_settings_recommendation_user_created (user_id, created_at),
    CONSTRAINT fk_settings_recommendation_user
        FOREIGN KEY (user_id) REFERENCES user(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_settings_recommendation_assessment
        FOREIGN KEY (assessment_id) REFERENCES assessment(assessment_id) ON DELETE CASCADE,
    CONSTRAINT fk_settings_recommendation_amplifier
        FOREIGN KEY (amplifier_profile_id)
        REFERENCES amplifier_profile(amplifier_profile_id) ON DELETE CASCADE,
    CONSTRAINT fk_settings_recommendation_parent
        FOREIGN KEY (parent_recommendation_id)
        REFERENCES settings_recommendation(recommendation_id) ON DELETE SET NULL,
    CONSTRAINT chk_settings_recommendation_scale
        CHECK (scale_min < scale_max AND scale_step > 0),
    CONSTRAINT chk_settings_recommendation_profile_pair
        CHECK (
            (genre_profile_version IS NULL AND genre_profile_checksum IS NULL)
            OR
            (genre_profile_version IS NOT NULL AND genre_profile_checksum IS NOT NULL)
        ),
    CONSTRAINT chk_settings_recommendation_available_profile
        CHECK (
            recommendation_status = 'unavailable'
            OR
            (genre_profile_version IS NOT NULL AND genre_profile_checksum IS NOT NULL)
        )
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
