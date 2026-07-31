-- 0021_wein — Lebensbereich „Wein": Weinkeller, Bewertungen und Preisbeobachtung.
--
-- WARUM diese drei Tabellen:
--  1) weine            : der Wein als Sache — Herkunft/Rebsorten/Geschmacksprofil + alles, was beim
--                        Erfassen per Etikettenfoto, EAN oder KI-Recherche zusammengetragen wird.
--                        Bewusst breit: die Erfassung soll EINMAL alles einsammeln (Story, Aromen,
--                        Speiseempfehlung, Trinkfenster), damit im Laden und am Esstisch nichts fehlt.
--                        `referenzpreis` ist die BASIS der Rabattrechnung (typischer Ladenpreis),
--                        `bester_preis*` der zuletzt gefundene Bestpreis, `gekauft_*` was WIR bezahlt haben.
--  2) wein_bewertungen : genau EINE Bewertung je (Wein, Person) — Lars und Elita bewerten getrennt
--                        (UNIQUE + UPSERT), damit „schon getrunken, fanden wir gut?" im Laden sofort
--                        beantwortbar ist. Kein Bewertungs-Log, sondern der aktuelle Stand je Person.
--  3) wein_preise      : Preis-HISTORIE (jede Recherche hängt eine Zeile an) → Preisverlauf sichtbar
--                        und Rabatte gegen den Referenzpreis erkennbar (Job `wein-preischeck`).
--
-- Enum-Spalten sind absichtlich als CHECK(spalte IN ('a','b')) geschrieben — server/db/constraints.ts
-- parst genau diese Form und macht daraus 422-Fehler + die `allowed`-Liste in /schema.
-- Geschmacksprofil (suesse/saeure/tannin/koerper) und Jahrgang sind NULL-bar: „unbekannt" ist ein
-- eigener, legitimer Zustand (jahrgangslose Sekte, unvollständige KI-Erkennung) — nie 0 raten.
-- Additiv & IF NOT EXISTS → sicher auf der geseedeten Prod-DB.

-- ── 1) Weine ──
CREATE TABLE IF NOT EXISTS "weine" (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  name                  TEXT NOT NULL,                        -- Weinname OHNE Weingut, z.B. "Barolo Riserva"
  weingut               TEXT NOT NULL DEFAULT '',
  jahrgang              INTEGER,                              -- NULL = jahrgangslos (viele Sekte/Champagner)
  typ                   TEXT NOT NULL DEFAULT 'rot'
                        CHECK(typ IN ('rot','weiss','rose','sekt','champagner','schaumwein','dessert','port','sonstiges')),
  rebsorten             TEXT NOT NULL DEFAULT '[]',           -- JSON-Array Strings, z.B. ["Nebbiolo"]
  land                  TEXT,
  region                TEXT,
  lage                  TEXT,                                 -- Einzellage/Weinberg
  alkohol               REAL,                                 -- Volumenprozent
  geschmacksrichtung    TEXT NOT NULL DEFAULT 'unbekannt'
                        CHECK(geschmacksrichtung IN ('trocken','halbtrocken','feinherb','lieblich','suess','brut nature','extra brut','brut','extra dry','sec','demi-sec','unbekannt')),
  suesse                INTEGER,                              -- Geschmacksprofil je 1..5, NULL = unbekannt
  saeure                INTEGER,
  tannin                INTEGER,
  koerper               INTEGER,
  aromen                TEXT NOT NULL DEFAULT '[]',           -- JSON-Array Tags, z.B. ["Kirsche","Vanille","Leder"]
  serviertemperatur     TEXT,                                 -- z.B. "16-18 °C"
  trinkfenster_von      INTEGER,                              -- Jahr
  trinkfenster_bis      INTEGER,                              -- Jahr
  bio                   INTEGER NOT NULL DEFAULT 0,
  vegan                 INTEGER NOT NULL DEFAULT 0,
  flaschengroesse_ml    INTEGER NOT NULL DEFAULT 750,
  ean                   TEXT,                                 -- Barcode (Einkaufs-Scan im Laden)
  beschreibung          TEXT,                                 -- Hintergrund/Story (Weingut, Lage, Ausbau)
  auszeichnungen        TEXT NOT NULL DEFAULT '[]',           -- JSON-Array, z.B. ["Falstaff 93","Parker 91"]
  speiseempfehlung      TEXT,
  referenzpreis         REAL,                                 -- typischer Ladenpreis = BASIS der Rabattrechnung
  bester_preis          REAL,                                 -- zuletzt gefundener Bestpreis
  bester_preis_haendler TEXT,
  bester_preis_url      TEXT,
  preis_geprueft_at     TEXT,                                 -- letzte Preisrecherche (steuert das Prüf-Intervall)
  gekauft_preis         REAL,                                 -- was WIR bezahlt haben
  gekauft_bei           TEXT,                                 -- … und wo
  preis_beobachten      INTEGER NOT NULL DEFAULT 1,           -- 1 = Job `wein-preischeck` beobachtet diesen Wein
  bestand               INTEGER NOT NULL DEFAULT 0,           -- Flaschen im Keller
  lagerort              TEXT,
  foto_key              TEXT,                                 -- Etikettenfoto (media area 'wein')
  quelle                TEXT NOT NULL DEFAULT 'manuell'       -- wie der Datensatz entstanden ist
                        CHECK(quelle IN ('manuell','foto','ean','ki')),
  ki_confidence         TEXT,                                 -- hoch | mittel | niedrig (Selbsteinschätzung der Erfassung)
  notizen               TEXT,
  created_at            TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at            TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_weine_typ      ON "weine"(typ);
CREATE INDEX IF NOT EXISTS idx_weine_identity ON "weine"(weingut, name, jahrgang);
CREATE INDEX IF NOT EXISTS idx_weine_ean      ON "weine"(ean);
CREATE INDEX IF NOT EXISTS idx_weine_bestand  ON "weine"(bestand);
CREATE INDEX IF NOT EXISTS idx_weine_preischeck ON "weine"(preis_beobachten, preis_geprueft_at);

-- ── 2) Bewertungen — genau EINE je (Wein, Person) ──
CREATE TABLE IF NOT EXISTS "wein_bewertungen" (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  wein_id    INTEGER NOT NULL REFERENCES "weine"(id) ON DELETE CASCADE,
  owner      TEXT NOT NULL CHECK(owner IN ('lars','elita')),
  sterne     INTEGER NOT NULL CHECK(sterne IN (1,2,3,4,5)),
  kommentar  TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (wein_id, owner)
);
CREATE INDEX IF NOT EXISTS idx_wein_bewertungen_wein ON "wein_bewertungen"(wein_id);

-- ── 3) Preis-Historie (Verlauf + Rabatt-Erkennung) ──
CREATE TABLE IF NOT EXISTS "wein_preise" (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  wein_id     INTEGER NOT NULL REFERENCES "weine"(id) ON DELETE CASCADE,
  preis       REAL NOT NULL,
  haendler    TEXT NOT NULL DEFAULT '',
  url         TEXT,
  quelle      TEXT NOT NULL DEFAULT 'perplexity'
              CHECK(quelle IN ('perplexity','manuell','ki')),
  gefunden_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_wein_preise_wein ON "wein_preise"(wein_id, gefunden_at DESC);

-- Registry-Eintrag fuer Portal/Capabilities (nativer iOS-Bereich routet ueber BEREICH_REGISTRY).
INSERT OR IGNORE INTO lebensbereiche (key, titel, beschreibung, emoji, gradient, api_base, sort, enabled)
VALUES ('wein', 'Wein', 'Weinkeller, Bewertungen & Preise', '🍷',
        'from-[#7F1D1D] via-[#9F1239] to-[#701A75]', '/api/v1/weine', 15, 1);
