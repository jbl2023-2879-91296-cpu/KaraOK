-- Compatibility migration for the supplied 2026-09-08 server schema.
-- Apply ONCE to karaok_db after backup, with application writes stopped.
-- MySQL DDL commits implicitly: a later failure does not undo earlier statements.
-- Do not run mysql --force. Inspect partial state before retrying.
-- Existing records and retired tables/columns are deliberately preserved.
-- Historical quality provenance is unknown: leave it NULL, never invent it.
-- This intentionally differs from the fresh-install NOT NULL declarations.
USE karaok_db;

ALTER TABLE audio_analysis_result
    ADD COLUMN quality_profile_version VARCHAR(30) NULL AFTER scoring_algorithm_version,
    ADD COLUMN quality_profile_checksum CHAR(64) NULL AFTER quality_profile_version;
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
