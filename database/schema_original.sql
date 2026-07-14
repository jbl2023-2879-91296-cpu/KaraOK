CREATE DATABASE karaok_db;
USE karaok_db;

-- ==========================================
-- TABLE: USER
-- ==========================================

CREATE TABLE user (
    user_id INT AUTO_INCREMENT PRIMARY KEY,

    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,

    role ENUM('Consumer','Technician') NOT NULL DEFAULT 'Consumer',

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==========================================
-- TABLE: GENRE PRESET
-- Stores the recommended sound settings
-- ==========================================

CREATE TABLE genre_preset (
    preset_id INT AUTO_INCREMENT PRIMARY KEY,

    genre_name VARCHAR(50) NOT NULL UNIQUE,

    bass FLOAT NOT NULL,
    treble FLOAT NOT NULL,
    loudness FLOAT NOT NULL,
    sharpness FLOAT NOT NULL,
    flatness FLOAT NOT NULL
);

-- ==========================================
-- TABLE: AUDIO QUALITY THRESHOLD
-- Stores empirical threshold values
-- ==========================================

CREATE TABLE audio_quality_threshold (
    threshold_id INT AUTO_INCREMENT PRIMARY KEY,

    threshold_name VARCHAR(100) NOT NULL,

    max_allowable_noise FLOAT NOT NULL,
    max_allowable_distortion FLOAT NOT NULL,
    min_quality_score FLOAT NOT NULL
);

-- ==========================================
-- TABLE: ASSESSMENT
-- One uploaded audio per assessment
-- ==========================================

CREATE TABLE assessment (
    assessment_id INT AUTO_INCREMENT PRIMARY KEY,

    user_id INT NOT NULL,

    audio_file_path VARCHAR(255),

    assessment_status ENUM('Pending','Processing','Completed','Failed')
        DEFAULT 'Pending',

    assessment_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    api_reference VARCHAR(100),

    processing_time FLOAT,

    CONSTRAINT fk_assessment_user
        FOREIGN KEY (user_id)
        REFERENCES user(user_id)
        ON DELETE CASCADE
);

-- ==========================================
-- TABLE: AUDIO ANALYSIS RESULT
-- Stores both quality assessment and
-- genre recommendation results
-- ==========================================

CREATE TABLE audio_analysis_result (
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