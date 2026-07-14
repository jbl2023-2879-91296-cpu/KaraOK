-- ============================================================
-- KaraOK Database Schema
-- Database : karaok_db
-- User     : root  |  Password : 12345678
-- ============================================================

CREATE DATABASE IF NOT EXISTS karaok_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE karaok_db;

-- ------------------------------------------------------------
-- Users
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
  id            INT          NOT NULL AUTO_INCREMENT,
  name          VARCHAR(100) NOT NULL,
  email         VARCHAR(150) UNIQUE,
  password_hash VARCHAR(64),
  user_type     ENUM('technician', 'owner') NOT NULL,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
);

-- ------------------------------------------------------------
-- Audio Tests  (Technician flow)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audio_tests (
  id                INT            NOT NULL AUTO_INCREMENT,
  user_id           INT,
  test_name         VARCHAR(100)   NOT NULL,
  score             INT            NOT NULL DEFAULT 0,
  noise_level       DECIMAL(6,2),
  distortion_level  DECIMAL(6,4),
  status            ENUM('Acceptable','Problematic') NOT NULL DEFAULT 'Acceptable',
  duration_seconds  INT            NOT NULL DEFAULT 0,
  created_at        DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
);

-- ------------------------------------------------------------
-- Genre Settings  (Owner flow)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genre_settings (
  id         INT          NOT NULL AUTO_INCREMENT,
  user_id    INT,
  genre      VARCHAR(50)  NOT NULL,
  volume     INT          NOT NULL DEFAULT 75,
  bass       INT          NOT NULL DEFAULT 55,
  treble     INT          NOT NULL DEFAULT 65,
  flatness   INT          NOT NULL DEFAULT 70,
  sharpness  INT          NOT NULL DEFAULT 90,
  updated_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                          ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
);

-- ------------------------------------------------------------
-- Audio Uploads  (Owner flow)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audio_uploads (
  id         INT          NOT NULL AUTO_INCREMENT,
  user_id    INT,
  file_name  VARCHAR(255) NOT NULL,
  genre      VARCHAR(50),
  score      INT,
  status     ENUM('Acceptable','Problematic') NOT NULL DEFAULT 'Acceptable',
  created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
);

-- ------------------------------------------------------------
-- Seed data — default genre settings
-- ------------------------------------------------------------
INSERT IGNORE INTO genre_settings (user_id, genre, volume, bass, treble, flatness, sharpness) VALUES
  (NULL, 'Rock',    85, 70, 75, 55, 90),
  (NULL, 'Classic', 65, 45, 70, 80, 60),
  (NULL, 'Pop',     80, 60, 70, 65, 80),
  (NULL, 'Ballad',  75, 55, 65, 70, 90),
  (NULL, 'HipHop',  90, 85, 50, 60, 75),
  (NULL, 'R&B',     78, 72, 62, 68, 82);

-- ------------------------------------------------------------
-- Migration: add auth columns to existing users table
-- Safe to run even if columns already exist
-- ------------------------------------------------------------
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS email         VARCHAR(150) UNIQUE AFTER name,
  ADD COLUMN IF NOT EXISTS password_hash VARCHAR(64)        AFTER email;
