-- Apply before deploying Noise Guard. Existing recordings keep unknown values.
-- MySQL DDL commits implicitly. Each column can be added independently on retry.
USE karaok_db;

SET @noise_guard_usable_pct_exists = (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'audio_analysis_result'
      AND column_name = 'noise_guard_usable_pct'
);
SET @noise_guard_usable_pct_ddl = IF(@noise_guard_usable_pct_exists = 0,
    'ALTER TABLE audio_analysis_result ADD COLUMN noise_guard_usable_pct FLOAT NULL',
    'SELECT 1'
);
PREPARE noise_guard_usable_pct_migration FROM @noise_guard_usable_pct_ddl;
EXECUTE noise_guard_usable_pct_migration;
DEALLOCATE PREPARE noise_guard_usable_pct_migration;

SET @noise_guard_confidence_exists = (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'audio_analysis_result'
      AND column_name = 'noise_guard_confidence'
);
SET @noise_guard_confidence_ddl = IF(@noise_guard_confidence_exists = 0,
    'ALTER TABLE audio_analysis_result ADD COLUMN noise_guard_confidence VARCHAR(10) NULL',
    'SELECT 1'
);
PREPARE noise_guard_confidence_migration FROM @noise_guard_confidence_ddl;
EXECUTE noise_guard_confidence_migration;
DEALLOCATE PREPARE noise_guard_confidence_migration;

SET @preroll_noise_dbfs_exists = (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'audio_analysis_result'
      AND column_name = 'preroll_noise_dbfs'
);
SET @preroll_noise_dbfs_ddl = IF(@preroll_noise_dbfs_exists = 0,
    'ALTER TABLE audio_analysis_result ADD COLUMN preroll_noise_dbfs FLOAT NULL',
    'SELECT 1'
);
PREPARE preroll_noise_dbfs_migration FROM @preroll_noise_dbfs_ddl;
EXECUTE preroll_noise_dbfs_migration;
DEALLOCATE PREPARE preroll_noise_dbfs_migration;

-- Rollback: deploy the previous application first, then run:
-- ALTER TABLE audio_analysis_result DROP COLUMN noise_guard_usable_pct,
--     DROP COLUMN noise_guard_confidence, DROP COLUMN preroll_noise_dbfs;
-- Dropping these columns permanently removes stored Noise Guard measurements.
