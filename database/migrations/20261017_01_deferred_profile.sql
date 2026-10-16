-- Apply before deploying simplified signup. Repeatable; preserves values and indexes.
USE karaok_db;

ALTER TABLE user
    MODIFY COLUMN first_name VARCHAR(80) NULL,
    MODIFY COLUMN last_name VARCHAR(80) NULL,
    MODIFY COLUMN address VARCHAR(255) NULL,
    MODIFY COLUMN city VARCHAR(100) NULL,
    MODIFY COLUMN state_province VARCHAR(100) NULL,
    MODIFY COLUMN area_code VARCHAR(20) NULL,
    MODIFY COLUMN country VARCHAR(80) NULL,
    MODIFY COLUMN country_code CHAR(2) NULL,
    MODIFY COLUMN phone_number VARCHAR(20) NULL,
    MODIFY COLUMN birthday DATE NULL;
