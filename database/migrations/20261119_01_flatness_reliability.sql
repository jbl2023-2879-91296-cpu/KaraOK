-- Add persisted flatness reliability for new analyses. Existing rows remain unknown.
USE karaok_db;

SET @flatness_reliable_ddl = IF(
    EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = DATABASE() AND table_name = 'audio_analysis_result'
          AND column_name = 'flatness_reliable'
    ),
    'SELECT 1',
    'ALTER TABLE audio_analysis_result ADD COLUMN flatness_reliable BOOLEAN NULL'
);
PREPARE flatness_reliability_migration FROM @flatness_reliable_ddl;
EXECUTE flatness_reliability_migration;
DEALLOCATE PREPARE flatness_reliability_migration;

SET @flatness_note_ddl = IF(
    EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = DATABASE() AND table_name = 'audio_analysis_result'
          AND column_name = 'flatness_reliability_note'
    ),
    'SELECT 1',
    'ALTER TABLE audio_analysis_result ADD COLUMN flatness_reliability_note VARCHAR(160) NULL'
);
PREPARE flatness_reliability_migration FROM @flatness_note_ddl;
EXECUTE flatness_reliability_migration;
DEALLOCATE PREPARE flatness_reliability_migration;
