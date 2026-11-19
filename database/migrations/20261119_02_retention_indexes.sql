-- Indexes for admin report date-range filters and the nightly retention cleanup.
-- Safe to re-run: each index is created only when it does not exist yet.
USE karaok_db;

SET @idx_user_role_created_ddl = IF(
    EXISTS (
        SELECT 1 FROM information_schema.statistics
        WHERE table_schema = DATABASE() AND table_name = 'user' AND index_name = 'idx_user_role_created'
    ),
    'SELECT 1',
    'ALTER TABLE `user` ADD INDEX idx_user_role_created (role, created_at)'
);
PREPARE idx_user_role_created_migration FROM @idx_user_role_created_ddl;
EXECUTE idx_user_role_created_migration;
DEALLOCATE PREPARE idx_user_role_created_migration;

SET @idx_assessment_date_ddl = IF(
    EXISTS (
        SELECT 1 FROM information_schema.statistics
        WHERE table_schema = DATABASE() AND table_name = 'assessment' AND index_name = 'idx_assessment_date'
    ),
    'SELECT 1',
    'ALTER TABLE `assessment` ADD INDEX idx_assessment_date (assessment_date)'
);
PREPARE idx_assessment_date_migration FROM @idx_assessment_date_ddl;
EXECUTE idx_assessment_date_migration;
DEALLOCATE PREPARE idx_assessment_date_migration;

SET @idx_settings_recommendation_created_ddl = IF(
    EXISTS (
        SELECT 1 FROM information_schema.statistics
        WHERE table_schema = DATABASE() AND table_name = 'settings_recommendation' AND index_name = 'idx_settings_recommendation_created'
    ),
    'SELECT 1',
    'ALTER TABLE `settings_recommendation` ADD INDEX idx_settings_recommendation_created (created_at)'
);
PREPARE idx_settings_recommendation_created_migration FROM @idx_settings_recommendation_created_ddl;
EXECUTE idx_settings_recommendation_created_migration;
DEALLOCATE PREPARE idx_settings_recommendation_created_migration;

SET @idx_refresh_token_expires_ddl = IF(
    EXISTS (
        SELECT 1 FROM information_schema.statistics
        WHERE table_schema = DATABASE() AND table_name = 'refresh_token' AND index_name = 'idx_refresh_token_expires'
    ),
    'SELECT 1',
    'ALTER TABLE `refresh_token` ADD INDEX idx_refresh_token_expires (expires_at)'
);
PREPARE idx_refresh_token_expires_migration FROM @idx_refresh_token_expires_ddl;
EXECUTE idx_refresh_token_expires_migration;
DEALLOCATE PREPARE idx_refresh_token_expires_migration;

SET @idx_revoked_access_token_expires_ddl = IF(
    EXISTS (
        SELECT 1 FROM information_schema.statistics
        WHERE table_schema = DATABASE() AND table_name = 'revoked_access_token' AND index_name = 'idx_revoked_access_token_expires'
    ),
    'SELECT 1',
    'ALTER TABLE `revoked_access_token` ADD INDEX idx_revoked_access_token_expires (expires_at)'
);
PREPARE idx_revoked_access_token_expires_migration FROM @idx_revoked_access_token_expires_ddl;
EXECUTE idx_revoked_access_token_expires_migration;
DEALLOCATE PREPARE idx_revoked_access_token_expires_migration;

SET @idx_registration_otp_expires_ddl = IF(
    EXISTS (
        SELECT 1 FROM information_schema.statistics
        WHERE table_schema = DATABASE() AND table_name = 'registration_otp' AND index_name = 'idx_registration_otp_expires'
    ),
    'SELECT 1',
    'ALTER TABLE `registration_otp` ADD INDEX idx_registration_otp_expires (expires_at)'
);
PREPARE idx_registration_otp_expires_migration FROM @idx_registration_otp_expires_ddl;
EXECUTE idx_registration_otp_expires_migration;
DEALLOCATE PREPARE idx_registration_otp_expires_migration;
