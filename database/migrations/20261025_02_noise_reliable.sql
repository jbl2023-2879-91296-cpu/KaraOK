-- Apply before deploying noise reliability. Old estimates remain unknown.
-- MySQL DDL commits implicitly. Repeat runs preserve stored reliability.
USE karaok_db;

SET @noise_reliable_exists = (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'audio_analysis_result'
      AND column_name = 'noise_reliable'
);
SET @noise_reliable_ddl = IF(@noise_reliable_exists = 0,
    'ALTER TABLE audio_analysis_result ADD COLUMN noise_reliable BOOLEAN NULL DEFAULT NULL',
    'SELECT 1'
);
PREPARE noise_reliable_migration FROM @noise_reliable_ddl;
EXECUTE noise_reliable_migration;
DEALLOCATE PREPARE noise_reliable_migration;

-- Rollback: deploy the previous application first, then run:
-- ALTER TABLE audio_analysis_result DROP COLUMN noise_reliable;
-- Dropping this column permanently removes stored reliability.
