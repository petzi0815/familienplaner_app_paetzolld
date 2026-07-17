-- 0015_pizza_mehle.sql — mehltyp-CHECK auf fuenf Mehlsorten erweitern (datenerhaltend)
--
-- Ziel: pizza_rezepte.mehltyp erlaubt statt nur ('tipo00','dinkel') jetzt
--   ('tipo00','dinkel','caputo_pizzeria','la_farina_14','edeka_herzstuecke').
-- SQLite kann einen CHECK nicht per ALTER aendern → Tabelle neu bauen (create+copy+swap).
--
-- WICHTIG (FK-Falle): pizza_notizen.rezept_id ist FK auf pizza_rezepte(id) mit ON DELETE CASCADE.
-- getDb() setzt PRAGMA foreign_keys=ON, und der Migrations-Runner (migrate.ts) fuehrt jede Datei
-- INNERHALB einer Transaktion aus. `PRAGMA foreign_keys` ist innerhalb einer offenen Transaktion
-- ein No-Op → FK-Enforcement bleibt AN und laesst sich hier NICHT abschalten.
-- Ein direktes `DROP TABLE pizza_rezepte` fuehrt daher einen impliziten DELETE aller Elternzeilen aus,
-- was ueber ON DELETE CASCADE ALLE pizza_notizen loeschen wuerde → Datenverlust.
-- Deshalb: die Notizen vor dem Parent-Swap zwischenlagern und leeren (dann kaskadiert nichts),
-- danach 1:1 (inkl. IDs) zurueckschreiben. Der FK referenziert die Tabelle per NAME → nach dem
-- RENAME zeigt er wieder korrekt auf die neue pizza_rezepte.

-- (1) Neue Parent-Tabelle mit IDENTISCHEM Schema wie pizza_rezepte NACH 0013+0014
--     (inkl. fridge_temp als letzter Spalte!), nur der mehltyp-CHECK ist erweitert.
CREATE TABLE "pizza_rezepte_new" (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  name              TEXT NOT NULL,
  anzahl_pizzen     INTEGER NOT NULL DEFAULT 6,
  teiglingsgewicht  INTEGER NOT NULL DEFAULT 275,
  mehltyp           TEXT NOT NULL DEFAULT 'tipo00' CHECK(mehltyp IN ('tipo00','dinkel','caputo_pizzeria','la_farina_14','edeka_herzstuecke')),
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
  updated_at        TEXT DEFAULT (datetime('now')),
  fridge_temp       REAL NOT NULL DEFAULT 5
);

-- (2) Alle Zeilen 1:1 kopieren (Spaltenreihenfolge identisch → SELECT * ist sicher; IDs bleiben).
INSERT INTO "pizza_rezepte_new" SELECT * FROM "pizza_rezepte";

-- (3) Notizen zwischenlagern und leeren, damit der Parent-DROP nicht kaskadiert.
CREATE TEMP TABLE "_pizza_notizen_stash" AS SELECT * FROM "pizza_notizen";
DELETE FROM "pizza_notizen";

-- (4) Parent tauschen.
DROP TABLE "pizza_rezepte";
ALTER TABLE "pizza_rezepte_new" RENAME TO "pizza_rezepte";

-- (5) Notizen 1:1 (inkl. IDs) zurueckschreiben; FK ist jetzt wieder gueltig.
INSERT INTO "pizza_notizen" SELECT * FROM "_pizza_notizen_stash";
DROP TABLE "_pizza_notizen_stash";

-- (6) Indizes von 0013 wiederherstellen. 0013 hatte KEINEN Index auf pizza_rezepte
--     (nur idx_pizza_notizen_rezept auf pizza_notizen, das unangetastet bleibt) → nichts nachzubauen.
