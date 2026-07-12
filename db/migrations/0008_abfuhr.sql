-- 0008_abfuhr — Abfuhrkalender: Müll-Abfuhrtermine (Restmüll, Gelbe Tonne, Bio, Papier).
-- Quelle: ICS-Upload oder Online-Sync (aha-region.de). Nächster Termin je Kategorie im Dashboard;
-- Vorabend-Push (19 Uhr) an die iOS-Geräte als Erinnerung.

CREATE TABLE IF NOT EXISTS abfuhr_termine (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  kategorie    TEXT NOT NULL,                          -- restmuell | gelbe_tonne | bio | papier | sonstige
  datum        TEXT NOT NULL,                          -- YYYY-MM-DD
  summary      TEXT,                                   -- Original-SUMMARY aus der ICS
  uid          TEXT UNIQUE,                            -- ICS-UID (idempotenter Import)
  quelle       TEXT NOT NULL DEFAULT 'ics',            -- ics | aha
  push_gesendet INTEGER NOT NULL DEFAULT 0,            -- Vorabend-Push schon raus?
  erstellt_am  TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_abfuhr_datum ON abfuhr_termine(datum);
CREATE INDEX IF NOT EXISTS idx_abfuhr_kat ON abfuhr_termine(kategorie, datum);

-- Adresse + Online-Sync-Parameter (aha-region.de).
CREATE TABLE IF NOT EXISTS abfuhr_config (
  id             INTEGER PRIMARY KEY CHECK (id = 1),
  strasse        TEXT,
  hausnummer     TEXT,
  plz            TEXT,
  ort            TEXT,
  aha_ics_url    TEXT,                                 -- direkte ICS-URL (falls ermittelt) → auto-sync
  letzter_sync   TEXT,
  aktualisiert_am TEXT NOT NULL DEFAULT (datetime('now'))
);
INSERT OR IGNORE INTO abfuhr_config (id, strasse, hausnummer, plz, ort)
VALUES (1, 'Wilhelm-Hanebuth-Weg', '7', '30938', 'Burgwedel');

-- Dashboard-Kachel (Web).
INSERT OR IGNORE INTO lebensbereiche (key, titel, beschreibung, emoji, gradient, api_base, sort)
VALUES ('abfuhrkalender', 'Abfuhrkalender', 'Müll-Abfuhrtermine', '🗑️',
        'from-[#10B981] via-[#34C759] to-[#84CC16]', '/api/v1/abfuhr-termine', 97);
