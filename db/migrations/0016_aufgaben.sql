-- 0016_aufgaben — Familien-Aufgaben (Tasks) als eigener, API-first Lebensbereich.
--
-- Aufgaben ≠ Termine: eine Aufgabe hat immer eine Beschreibung + eine/n Zuständige/n (Lars/Elita/Familie),
-- ist optional terminiert (due_date; ohne = unterminiert), kann mit einem Termin verknüpft sein
-- (termin_id), kann sich in einem Intervall wiederholen (recurring) und wird abgehakt (status).
-- Quelle „garten" liefert zusätzlich Aufgaben aus dem Gartenplaner (read/complete über garten_aufgaben).
-- Über /api/v1/aufgaben (generisches CRUD) + /api/v1/aufgaben/{id}/complete von außen (Ole/API) befüllbar.
-- Additiv & IF NOT EXISTS → sicher auf der geseedeten Prod-DB.

CREATE TABLE IF NOT EXISTS aufgaben (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  title       TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',                                   -- Pflicht (fachlich); leer nur als Fallback
  owner       TEXT NOT NULL DEFAULT 'familie'                            -- Zuständig
              CHECK(owner IN ('lars', 'elita', 'familie')),
  due_date    TEXT,                                                       -- YYYY-MM-DD (optional; NULL = unterminiert)
  termin_id   INTEGER REFERENCES termine(id) ON DELETE SET NULL,         -- optionale Verknüpfung zu einem Termin
  project     TEXT,                                                       -- optionales Projekt-/Sammel-Label (Familienprojekte)
  status      TEXT NOT NULL DEFAULT 'offen'
              CHECK(status IN ('offen', 'erledigt')),
  priority    TEXT NOT NULL DEFAULT 'normal'
              CHECK(priority IN ('niedrig', 'normal', 'hoch')),
  recurring   TEXT NOT NULL DEFAULT 'einmalig'                           -- Wiederholung; 'einmalig' = keine
              CHECK(recurring IN ('einmalig', 'taeglich', 'woechentlich', 'monatlich', 'jaehrlich')),
  source      TEXT NOT NULL DEFAULT 'manuell',                           -- manuell | ole | api | projekt | garten | …
  notes       TEXT,
  done_at     TEXT,                                                       -- letzte Erledigung (auch bei recurring)
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_aufgaben_status ON aufgaben(status, due_date);
CREATE INDEX IF NOT EXISTS idx_aufgaben_owner ON aufgaben(owner);
CREATE INDEX IF NOT EXISTS idx_aufgaben_termin ON aufgaben(termin_id);
