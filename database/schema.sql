CREATE DATABASE IF NOT EXISTS karaok_db;
USE karaok_db;

-- ==========================================
-- ORIGINAL TABLE: USER
-- ==========================================

CREATE TABLE IF NOT EXISTS user (
    user_id INT AUTO_INCREMENT PRIMARY KEY,

    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,

    -- Kept as a string so roles are extensible; no user-type ENUM is used.
    role VARCHAR(30) NOT NULL DEFAULT 'Consumer',

    -- Merged from the former user_security table.
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    security_updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==========================================
-- ORIGINAL TABLE: GENRE PRESET
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
-- ORIGINAL TABLE: AUDIO QUALITY THRESHOLD
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
-- ORIGINAL TABLE: ASSESSMENT
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

    -- Merged from the former assessment_metadata table.
    test_name VARCHAR(120),
    duration_seconds INT NOT NULL DEFAULT 0,
    result_status VARCHAR(30) NOT NULL DEFAULT 'Acceptable',

    CONSTRAINT fk_assessment_user
        FOREIGN KEY (user_id)
        REFERENCES user(user_id)
        ON DELETE CASCADE
);

-- ==========================================
-- ORIGINAL TABLE: AUDIO ANALYSIS RESULT
-- Stores quality assessment and genre recommendation results
-- ==========================================

CREATE TABLE IF NOT EXISTS audio_analysis_result (
    result_id INT AUTO_INCREMENT PRIMARY KEY,

    assessment_id INT NOT NULL UNIQUE,

    threshold_id INT NOT NULL,

    preset_id INT NOT NULL,

    quality_score FLOAT,

    noise_level FLOAT,

    distortion_level FLOAT,

    bass FLOAT,

    treble FLOAT,

    loudness FLOAT,

    sharpness FLOAT,

    flatness FLOAT,

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
-- ADDITIVE TABLE: REFRESH TOKEN
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
    CONSTRAINT fk_refresh_token_user
        FOREIGN KEY (user_id) REFERENCES user(user_id) ON DELETE CASCADE
);

-- ==========================================
-- ADDITIVE TABLE: PASSWORD RESET TOKEN
-- ==========================================

CREATE TABLE IF NOT EXISTS password_reset_token (
    reset_token_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    token_hash CHAR(64) NOT NULL UNIQUE,
    expires_at DATETIME NOT NULL,
    used_at DATETIME NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_password_reset_user
        FOREIGN KEY (user_id) REFERENCES user(user_id) ON DELETE CASCADE
);

-- ==========================================
-- ADDITIVE TABLE: REVOKED ACCESS TOKEN
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
-- ADDITIVE TABLE: AUDIT LOG
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
    CONSTRAINT fk_audit_log_user
        FOREIGN KEY (user_id) REFERENCES user(user_id) ON DELETE SET NULL
);

-- ==========================================
-- ADDITIVE TABLE: USER GENRE SETTINGS
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
-- ADDITIVE TABLE: AUDIO UPLOAD RECORD
-- ==========================================

CREATE TABLE IF NOT EXISTS audio_upload (
    upload_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    assessment_id INT NULL,
    file_name VARCHAR(255) NOT NULL,
    genre_name VARCHAR(50) NULL,
    score FLOAT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'Acceptable',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_audio_upload_user
        FOREIGN KEY (user_id) REFERENCES user(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_audio_upload_assessment
        FOREIGN KEY (assessment_id) REFERENCES assessment(assessment_id) ON DELETE SET NULL
);

CREATE INDEX idx_assessment_user_date
    ON assessment (user_id, assessment_date);
CREATE INDEX idx_refresh_token_user
    ON refresh_token (user_id, revoked_at, expires_at);
CREATE INDEX idx_password_reset_user
    ON password_reset_token (user_id, used_at, expires_at);
CREATE INDEX idx_audit_log_created
    ON audit_log (created_at);
CREATE INDEX idx_audio_upload_user_date
    ON audio_upload (user_id, created_at);

-- ==========================================
-- ADDITIVE TABLE: REGISTRATION OTP
-- Stores only pending registration data and a hash of the email code.
-- ==========================================

CREATE TABLE IF NOT EXISTS registration_otp (
    registration_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(30) NOT NULL DEFAULT 'Consumer',
    code_hash CHAR(64) NOT NULL,
    expires_at DATETIME NOT NULL,
    verified_at DATETIME NULL,
    attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_registration_otp_email (email)
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

INSERT IGNORE INTO audio_quality_threshold
    (threshold_name, max_allowable_noise, max_allowable_distortion, min_quality_score)
VALUES
    ('Default', 10, 5, 60);
