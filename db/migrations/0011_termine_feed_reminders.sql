-- 0011_termine_feed_reminders — Kalender-Abo-Feed, generische Erinnerungen, Per-User-Termin-Zustand.
--
--  1) feed_tokens        : Klartext-Token für abonnierbare ICS-Feeds (Kalender-Apps senden keinen Bearer →
--                          Token steckt im URL-Pfad). Ein Familien-Token (scope='family').
--  2) reminders          : generische, per-API befüllbare Erinnerungen/Ereignisse für das „Anstehendes"-Interface.
--  3) termin_user_state  : Per-User (owner) „gelesen"-Häkchen + Benachrichtigungs-Opt-in + Idempotenz-Marker
--                          für die 2-Tage-/1-Tag-Push (zwei Flags, da ein einzelnes Boolean zwei Sends nicht abbildet).
-- Alles additiv & IF NOT EXISTS → sicher auf der geseedeten Prod-DB.

-- ── 1) Abo-Feed-Token ──
CREATE TABLE IF NOT EXISTS feed_tokens (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  token        TEXT NOT NULL UNIQUE,                   -- zufälliger URL-sicherer Token (im Abo-Link)
  scope        TEXT NOT NULL DEFAULT 'family',         -- 'family' | 'lars' | 'elita' (künftig per-User)
  label        TEXT,
  revoked      INTEGER NOT NULL DEFAULT 0,
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  last_used_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_feed_tokens_scope ON feed_tokens(scope);

-- ── 2) Generische Erinnerungen (injizierbar via /api/v1/reminders) ──
CREATE TABLE IF NOT EXISTS reminders (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  title       TEXT NOT NULL,
  body        TEXT,
  date        TEXT NOT NULL,                           -- YYYY-MM-DD (Fälligkeit)
  time        TEXT,                                    -- HH:MM (optional)
  domain      TEXT,                                    -- optionaler Lebensbereich-Key (Icon/Farbe)
  owner       TEXT,                                    -- 'lars' | 'elita' | NULL (Familie)
  source      TEXT NOT NULL DEFAULT 'api',             -- api | ole | system | <domain>
  priority    INTEGER NOT NULL DEFAULT 0,
  status      TEXT NOT NULL DEFAULT 'offen',           -- offen | erledigt | verworfen
  push        INTEGER NOT NULL DEFAULT 0,              -- soll gepusht werden?
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_reminders_date ON reminders(date);
CREATE INDEX IF NOT EXISTS idx_reminders_status ON reminders(status, date);

-- ── 3) Per-User-Termin-Zustand ──
CREATE TABLE IF NOT EXISTS termin_user_state (
  termin_id        INTEGER NOT NULL,
  owner            TEXT NOT NULL,                      -- 'lars' | 'elita'
  read             INTEGER NOT NULL DEFAULT 0,         -- persönlich „gelesen" (unabhängig vom geteilten Status)
  notify           INTEGER NOT NULL DEFAULT 0,         -- Push-Opt-in dieses Users für diesen Termin
  reminder_2d_sent INTEGER NOT NULL DEFAULT 0,         -- 2-Tage-Vorab-Push raus?
  reminder_1d_sent INTEGER NOT NULL DEFAULT 0,         -- 1-Tag-Vorab-Push raus?
  updated_at       TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (termin_id, owner)
);
CREATE INDEX IF NOT EXISTS idx_termin_user_state_owner ON termin_user_state(owner);
CREATE INDEX IF NOT EXISTS idx_termin_user_state_notify ON termin_user_state(notify);
