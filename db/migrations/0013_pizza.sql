-- 0013_pizza.sql — Lebensbereich "Pizza machen"
-- Rein datenhaltend: das Backend speichert nur Rezepturen (Konfigurationen) + Verkostungs-Notizen.
-- Die komplette Teig-/Zeitplan-Berechnung passiert auf dem iPhone — hier gibt es KEINE Rechenlogik
-- und keine Web-UI. Bedient wird alles vom generischen CRUD (registry.ts: pizza-rezepte / pizza-notizen).

-- Eine gespeicherte Rezeptur/Konfiguration. NULL-Spalten (mehltemp, hydration) bedeuten
-- "Default vom Client ableiten": mehltemp = raumtemp, hydration = Default aus mehltyp.
CREATE TABLE IF NOT EXISTS "pizza_rezepte" (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  name              TEXT NOT NULL,
  anzahl_pizzen     INTEGER NOT NULL DEFAULT 6,
  teiglingsgewicht  INTEGER NOT NULL DEFAULT 275,
  mehltyp           TEXT NOT NULL DEFAULT 'tipo00' CHECK(mehltyp IN ('tipo00','dinkel')),
  hefetyp           TEXT NOT NULL DEFAULT 'frisch' CHECK(hefetyp IN ('frisch','trocken')),
  raumtemp          REAL NOT NULL DEFAULT 22,
  mehltemp          REAL,
  knetmethode       TEXT NOT NULL DEFAULT 'maschine' CHECK(knetmethode IN ('maschine','hand')),
  hydration         REAL,
  k_faktor          REAL NOT NULL DEFAULT 4.5,
  schlaf_von        TEXT NOT NULL DEFAULT '23:00',
  schlaf_bis        TEXT NOT NULL DEFAULT '07:00',
  favorit           INTEGER NOT NULL DEFAULT 0,
  notiz             TEXT,
  created_at        TEXT DEFAULT (datetime('now')),
  updated_at        TEXT DEFAULT (datetime('now'))
);

-- Verkostungs-/Variations-Log: mehrere zeitgestempelte Kommentare je Rezeptur, damit
-- nachgehalten werden kann was variiert wurde und wie das Ergebnis war.
CREATE TABLE IF NOT EXISTS "pizza_notizen" (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  rezept_id    INTEGER NOT NULL REFERENCES "pizza_rezepte"(id) ON DELETE CASCADE,
  text         TEXT NOT NULL,
  bewertung    INTEGER CHECK(bewertung BETWEEN 1 AND 5),
  gebacken_am  TEXT,
  created_at   TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_pizza_notizen_rezept ON "pizza_notizen"(rezept_id);

-- Registry-Eintrag fuer Portal/Capabilities (nativer iOS-Bereich routet ueber BEREICH_REGISTRY).
INSERT OR IGNORE INTO lebensbereiche (key, titel, emoji, gradient, sort, enabled)
VALUES ('pizza', 'Pizza machen', '🍕', 'from-[#DC2626] via-[#EA580C] to-[#65A30D]', 14, 1);
