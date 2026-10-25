-- Apply before deploying recommendation feedback. Existing rows remain unanswered.
-- MySQL DDL commits implicitly. Repeat runs preserve answers already collected.
USE karaok_db;

SET @feedback_exists = (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'settings_recommendation'
      AND column_name = 'feedback'
);
SET @feedback_ddl = IF(@feedback_exists = 0,
    'ALTER TABLE settings_recommendation ADD COLUMN feedback ENUM(''better'',''same'',''worse'') NULL DEFAULT NULL',
    'SELECT 1'
);
PREPARE feedback_migration FROM @feedback_ddl;
EXECUTE feedback_migration;
DEALLOCATE PREPARE feedback_migration;

-- Rollback: deploy the previous application first. Export feedback if it is needed,
-- then run: ALTER TABLE settings_recommendation DROP COLUMN feedback;
-- Dropping this column permanently removes the collected answers.
