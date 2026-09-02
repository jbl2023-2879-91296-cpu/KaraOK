-- KaraOK additive migration: versioned amplifier settings recommendations
-- Date: 2026-09-02
--
-- Apply to an existing KaraOK database after its user and assessment tables
-- exist. The migration is additive and intentionally contains no destructive
-- data or table operations.

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
    genre_profile_version VARCHAR(30) NOT NULL,
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
        REFERENCES settings_recommendation(recommendation_id) ON DELETE SET NULL
);
