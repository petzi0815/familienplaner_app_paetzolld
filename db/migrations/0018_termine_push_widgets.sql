-- 0018_termine_push_widgets — Termin-Push (Quittieren/Stumm), Widget-Feed und Live Activities.
--
--  1) termin_user_state  : + `muted` (dieser User will für DIESEN Termin keine Erinnerung mehr),
--                          + `reminder_0d_sent` (Idempotenz-Marker für den Push AM Termintag —
--                            ergänzt die bestehenden 2d-/1d-Marker) und + `ack_at` (Zeitpunkt der
--                            Quittierung vom Sperrbildschirm aus).
--  2) live_activity_tokens   : APNs-Tokens für Live Activities. `kind='start'` = push-to-start-Token
--                              (eins pro Gerät, startet neue Activities), `kind='update'` = Token einer
--                              KONKRET laufenden Activity (Update/Ende).
--  3) termin_live_activities : je (termin, owner) EINE laufende Activity → Idempotenz für Start/Update/Ende.
--
-- Alles additiv (ALTER … ADD COLUMN mit NOT NULL DEFAULT bzw. nullable) & IF NOT EXISTS
-- → sicher auf der geseedeten Prod-DB. `termine` selbst wird NICHT angefasst.

-- ── 1) Per-User-Termin-Zustand erweitern ──
ALTER TABLE termin_user_state ADD COLUMN muted            INTEGER NOT NULL DEFAULT 0;  -- 1 = nicht mehr erinnern
ALTER TABLE termin_user_state ADD COLUMN reminder_0d_sent INTEGER NOT NULL DEFAULT 0;  -- Push am Termintag raus?
ALTER TABLE termin_user_state ADD COLUMN ack_at           TEXT;                        -- datetime('now') der Quittierung

CREATE INDEX IF NOT EXISTS idx_termin_user_state_muted ON termin_user_state(muted);

-- ── 2) Live-Activity-Tokens ──
CREATE TABLE IF NOT EXISTS live_activity_tokens (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  token        TEXT NOT NULL UNIQUE,                  -- APNs-Live-Activity-Token (hex)
  kind         TEXT NOT NULL DEFAULT 'start',         -- 'start' (push-to-start, pro Gerät) | 'update' (pro Activity)
  owner        TEXT,                                  -- 'lars' | 'elita' | NULL (unbekannt/Legacy)
  activity_id  TEXT,                                  -- ActivityKit-ID (nur bei kind='update')
  termin_id    INTEGER,                               -- zugehöriger Termin (nur bei kind='update')
  environment  TEXT NOT NULL DEFAULT 'production',    -- production | sandbox
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen    TEXT
);
CREATE INDEX IF NOT EXISTS idx_live_activity_tokens_kind     ON live_activity_tokens(kind, owner);
CREATE INDEX IF NOT EXISTS idx_live_activity_tokens_activity ON live_activity_tokens(activity_id);
CREATE INDEX IF NOT EXISTS idx_live_activity_tokens_termin   ON live_activity_tokens(termin_id);

-- ── 3) Laufende Live Activities je (Termin, owner) ──
CREATE TABLE IF NOT EXISTS termin_live_activities (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  termin_id   INTEGER NOT NULL,
  owner       TEXT NOT NULL,                          -- 'lars' | 'elita'
  activity_id TEXT,                                   -- von der App gemeldete ActivityKit-ID (falls bekannt)
  status      TEXT NOT NULL DEFAULT 'bevorstehend',   -- bevorstehend | laeuft | quittiert | vorbei
  started_at  TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at  TEXT NOT NULL DEFAULT (datetime('now')),
  ended_at    TEXT,                                   -- gesetzt, sobald das 'end'-Event raus ist
  UNIQUE (termin_id, owner)
);
CREATE INDEX IF NOT EXISTS idx_termin_live_activities_open  ON termin_live_activities(ended_at, termin_id);
CREATE INDEX IF NOT EXISTS idx_termin_live_activities_owner ON termin_live_activities(owner);
