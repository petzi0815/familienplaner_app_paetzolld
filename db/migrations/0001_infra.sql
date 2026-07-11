-- 0001_infra — Infrastruktur-Tabellen (Registry, Auth, Jobs, Media, Audit, Verträge, Escape-Hatch)
-- Konsolidierte SQLite unter $DATA_DIR/familienplaner.db. Domänen-Tabellen: siehe 0002_domains.sql.

-- Lebensbereiche-Registry — steuert das Dashboard datengetrieben (offen erweiterbar).
CREATE TABLE IF NOT EXISTS lebensbereiche (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  key           TEXT NOT NULL UNIQUE,
  titel         TEXT NOT NULL,
  beschreibung  TEXT,
  emoji         TEXT,
  gradient      TEXT,
  api_base      TEXT,
  sort          INTEGER NOT NULL DEFAULT 0,
  enabled       INTEGER NOT NULL DEFAULT 1,
  schema_ref    TEXT,
  erstellt_am   TEXT NOT NULL DEFAULT (datetime('now'))
);

-- App-Settings (Runtime-Config via PUT /api/v1/config).
CREATE TABLE IF NOT EXISTS app_settings (
  key         TEXT PRIMARY KEY,
  value       TEXT,
  updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- API-Keys (rollenbasiert) — Agent „Ole" etc. Key wird nur als Hash gespeichert.
CREATE TABLE IF NOT EXISTS api_keys (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  label        TEXT,
  key_hash     TEXT NOT NULL UNIQUE,
  role         TEXT NOT NULL DEFAULT 'agent',   -- admin | agent | readonly
  last_used_at TEXT,
  revoked      INTEGER NOT NULL DEFAULT 0,
  created_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Web-UI-Sessions (Familien-Passwort-Login).
CREATE TABLE IF NOT EXISTS sessions (
  id          TEXT PRIMARY KEY,                -- zufälliger Token
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  expires_at  TEXT NOT NULL,
  user_label  TEXT
);

-- Job-Runs — idempotente Jobs mit Run-Logs.
CREATE TABLE IF NOT EXISTS job_runs (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  name          TEXT NOT NULL,
  schedule      TEXT,
  started_at    TEXT NOT NULL DEFAULT (datetime('now')),
  finished_at   TEXT,
  status        TEXT NOT NULL DEFAULT 'running', -- running | ok | error
  error         TEXT,
  messages      TEXT,                            -- JSON
  affected_rows INTEGER,
  dry_run       INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_job_runs_name ON job_runs(name, started_at);

-- Media-Assets — stabile Storage-Keys (<bereich>/<datei>) statt Zufallspfade.
CREATE TABLE IF NOT EXISTS media_assets (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  bereich       TEXT NOT NULL,
  storage_key   TEXT NOT NULL UNIQUE,
  original_name TEXT,
  mime          TEXT,
  bytes         INTEGER,
  sha256        TEXT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Audit-Log — welche API-Aktion hat was geändert.
CREATE TABLE IF NOT EXISTS event_log (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  ts        TEXT NOT NULL DEFAULT (datetime('now')),
  actor     TEXT,                 -- session | api-key-label
  action    TEXT NOT NULL,        -- create | update | delete | job | config
  domain    TEXT,
  entity_id TEXT,
  detail    TEXT                  -- JSON
);
CREATE INDEX IF NOT EXISTS idx_event_log_ts ON event_log(ts);

-- Generischer Escape-Hatch für spontane neue Bereiche ohne eigenes Schema.
CREATE TABLE IF NOT EXISTS entries (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  bereich_key    TEXT NOT NULL,
  typ            TEXT,
  titel          TEXT,
  daten          TEXT,            -- JSON custom fields
  bild_key       TEXT,
  status         TEXT,
  erstellt_am    TEXT NOT NULL DEFAULT (datetime('now')),
  aktualisiert_am TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_entries_bereich ON entries(bereich_key);

-- Verträge (bisher vertraege.json) — jetzt tabellarisch.
CREATE TABLE IF NOT EXISTS vertraege (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  kategorie        TEXT,
  anbieter         TEXT,
  bezeichnung      TEXT,
  kundennummer     TEXT,
  vertragsnummer   TEXT,
  kosten           REAL,
  kosten_intervall TEXT,
  beginn           TEXT,
  laufzeit_bis     TEXT,
  kuendigungsfrist TEXT,
  verlaengerung    TEXT,
  status           TEXT DEFAULT 'aktiv',
  notizen          TEXT,
  metadata         TEXT,          -- JSON: Rohdaten aus vertraege.json
  erstellt_am      TEXT NOT NULL DEFAULT (datetime('now')),
  aktualisiert_am  TEXT NOT NULL DEFAULT (datetime('now'))
);
