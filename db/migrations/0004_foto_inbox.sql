-- 0004_foto_inbox — Foto-Eingang: einzelne Fotos hochladen, grob einem Bereich zuordnen,
-- Status "neu" → der Agent (Ole) holt, analysiert, kategorisiert und ordnet Datensätzen zu.
CREATE TABLE IF NOT EXISTS foto_inbox (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  storage_key         TEXT NOT NULL,                 -- <bereich>/<datei> unter /data/media (via /api/v1/media/<key>)
  bereich             TEXT,                           -- Ziel-Lebensbereich (key), grobe Zuordnung durch den Uploader
  status              TEXT NOT NULL DEFAULT 'neu'
                        CHECK(status IN ('neu','in_bearbeitung','zugeordnet','verworfen')),
  notiz               TEXT,                           -- optionale Notiz vom Uploader (iOS)
  quelle              TEXT,                           -- 'ios' | 'web' | 'api'
  bytes               INTEGER,
  mime                TEXT,
  analyse             TEXT,                           -- JSON: Ergebnis der Agenten-Analyse
  zugeordnet_resource TEXT,                           -- z.B. 'samu-items' (woraus der Agent es machte)
  zugeordnet_id       TEXT,
  aufgenommen_am      TEXT,                           -- Client-/EXIF-Zeitstempel
  erstellt_am         TEXT NOT NULL DEFAULT (datetime('now')),
  aktualisiert_am     TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_foto_inbox_status ON foto_inbox(status);

-- Dashboard-Kachel für den Foto-Eingang.
INSERT OR IGNORE INTO lebensbereiche (key, titel, beschreibung, emoji, gradient, api_base, sort)
VALUES ('foto', 'Foto-Eingang', 'Fotos hochladen — Ole ordnet zu', '📸', 'from-[#5AC8FA] via-[#007AFF] to-[#5856D6]', '/api/v1/foto-inbox', 99);
