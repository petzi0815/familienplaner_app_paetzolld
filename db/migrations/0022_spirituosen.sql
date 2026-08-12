-- 0022_spirituosen — aus dem Lebensbereich „Wein" wird „Wein & Spirituosen".
--
-- WARUM EINE gemeinsame Tabelle statt einer zweiten `spirituosen`:
-- Alles, was um die Flasche herum passiert, ist für Whisky und Barolo IDENTISCH — genau EINE
-- Bewertung je Person (`wein_bewertungen`), die Preis-Historie (`wein_preise`), der nächtliche
-- Preis-Wächter (Job `wein-preischeck`), Keller/Bestand/Lagerort, der Einkaufs-Scan im Laden,
-- die Dublettenerkennung und das Etikettenfoto. Eine zweite Tabelle würde diese Logik samt Job
-- und Scan verdoppeln, ohne dass fachlich etwas gewonnen wäre. Unterschiedlich sind nur die
-- BESCHREIBENDEN Felder — und die kommen hier als NULL-bare Zusatzspalten dazu. Getrennt werden
-- die beiden Welten über die neue Spalte `art`; Fremdfelder der jeweils anderen Art werden schon
-- beim Erfassen verworfen (server/wein/enrich.ts), damit keine Halluzination in die Zeile kommt.
--
-- WARUM `art` NOT NULL mit DEFAULT 'wein':
-- Die Tabelle trägt in Prod ausschließlich echte Weine — jede Bestandszeile bekommt also den
-- fachlich richtigen Wert geschenkt, ohne Nachpflege. NOT NULL, weil „unbekannte Getränkeart"
-- kein sinnvoller Zustand ist: die App muss immer entscheiden können, welche Maske sie zeigt.
-- Der Default hält außerdem die bereits installierte App (Build 58) am Leben, die `art` nicht kennt.
--
-- WARUM `fuellstand_prozent` eine Zahl mit BETWEEN statt eines Enums („halb", „Neige"):
-- Die App zeichnet daraus einen Balken und rechnet mit dem Wert; ein Enum müsste dafür an jeder
-- Stelle wieder in eine Zahl übersetzt werden. Die Stufen-Auswahl in der Oberfläche ist nur eine
-- bequeme EINGABE auf denselben Zahlenraum (100/75/50/25/10/0). NULL = nie erfasst (Regel: nie 0
-- raten, sonst sieht eine ungeöffnete Flasche leer aus).
--
-- Enum-Spalten stehen bewusst als CHECK(spalte IN ('a','b')) INLINE an der Spalte — server/db/
-- constraints.ts parst genau diese Form aus sqlite_master und macht daraus 422-Fehler + die
-- `allowed`-Liste in /schema. Das BETWEEN-CHECK matcht diese Regex absichtlich nicht: 0..100 ist
-- keine Auswahlliste und gehört nicht als Aufzählung ins Schema.
--
-- Additiv (ALTER TABLE ADD COLUMN, kein Table-Rebuild) — Prod trägt echte Weindaten, ein Rebuild
-- wäre vermeidbares Risiko. SQLite kennt kein "ADD COLUMN IF NOT EXISTS", aber der Migrations-
-- Tracker (schema_migrations) führt jede Datei genau einmal aus → ein simples ALTER genügt.
-- SQLite erlaubt bei ADD COLUMN CHECK-Klauseln, aber kein PRIMARY KEY/UNIQUE; NOT NULL nur mit
-- Default (deshalb tragen `art` und `cocktails` einen).

-- ── Getränkeart: trennt Wein von Spirituose in derselben Tabelle ──
ALTER TABLE "weine" ADD COLUMN art TEXT NOT NULL DEFAULT 'wein'
                   CHECK(art IN ('wein','spirituose'));

-- ── Nur für Spirituosen: beschreibende Felder statt Rebsorten/Lage/Geschmacksprofil ──
ALTER TABLE "weine" ADD COLUMN kategorie TEXT                   -- Whisky, Gin, Rum … (nur Spirituosen)
                   CHECK(kategorie IN ('whisky','gin','rum','wodka','tequila','mezcal','cognac','brandy','grappa','obstbrand','likoer','aperitif','wermut','absinth','sonstiges'));
ALTER TABLE "weine" ADD COLUMN stil TEXT;                       -- Unterart, z.B. "Single Malt Islay", "London Dry", "Añejo"
ALTER TABLE "weine" ADD COLUMN alter_jahre INTEGER;             -- Altersangabe in Jahren; NULL = ohne (NAS)
ALTER TABLE "weine" ADD COLUMN fass TEXT;                       -- Reifung/Finish, z.B. "Ex-Bourbon, Oloroso-Finish"
ALTER TABLE "weine" ADD COLUMN abgefuellt_jahr INTEGER;         -- Abfülljahr (Single Cask/Batch) — nicht der Jahrgang
ALTER TABLE "weine" ADD COLUMN trinkempfehlung TEXT;            -- "pur", "on the rocks", "Gin Tonic mit …"
ALTER TABLE "weine" ADD COLUMN cocktails TEXT NOT NULL DEFAULT '[]';  -- JSON-Array Strings, z.B. ["Negroni","Martini"]

-- ── Angebrochene Flaschen (die Bar, anders als der Weinkeller, lebt von halbvollen Flaschen) ──
ALTER TABLE "weine" ADD COLUMN angebrochen_at TEXT;             -- ISO-Datum des Öffnens; NULL = ungeöffnet
ALTER TABLE "weine" ADD COLUMN fuellstand_prozent INTEGER       -- grober Füllstand, NULL = nie erfasst
                   CHECK(fuellstand_prozent BETWEEN 0 AND 100);

-- Die Listen filtern immer zuerst nach `art`, die Spirituosen-Ansicht zusätzlich nach `kategorie`.
CREATE INDEX IF NOT EXISTS idx_weine_art       ON "weine"(art);
CREATE INDEX IF NOT EXISTS idx_weine_kategorie ON "weine"(kategorie);

-- Anzeigetexte des Lebensbereichs nachziehen. Der Key bleibt 'wein' — daran hängen Routen,
-- BEREICH_REGISTRY und die bereits installierte App; nur die Beschriftung ändert sich.
UPDATE lebensbereiche
   SET titel = 'Wein & Spirituosen',
       beschreibung = 'Weinkeller, Bar, Bewertungen & Preise'
 WHERE key = 'wein';
