-- Textractor History Database Schema
-- Migrations for SQLite history store

CREATE TABLE IF NOT EXISTS capture_history (
    id TEXT PRIMARY KEY,
    text TEXT NOT NULL,
    confidence REAL NOT NULL DEFAULT 0.0,
    timestamp TEXT NOT NULL,
    metadata TEXT,
    mode TEXT NOT NULL DEFAULT 'region',
    ocr_language TEXT NOT NULL DEFAULT 'eng',
    processing_time_ms INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_history_timestamp ON capture_history(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_history_mode ON capture_history(mode);
CREATE INDEX IF NOT EXISTS idx_history_confidence ON capture_history(confidence DESC);
CREATE INDEX IF NOT EXISTS idx_history_text ON capture_history(text);