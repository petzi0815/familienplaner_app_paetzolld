-- 0024_wein_queue — Flaschen zuerst einsammeln, die KI-Erkennung danach im Hintergrund.
--
-- ANLASS: Beim Inventarisieren steht man mit der Flasche in der Hand vor dem Regal und will
-- auslösen, nicht warten. Die KI-Kette (Etikett → Recherche → Normalisierung) braucht aber
-- Sekunden bis Minuten. Also wird die Flasche SOFORT angelegt und die Anreicherung nachgereicht.
--
-- WARUM DER WARTESCHLANGEN-ZUSTAND AN DER FLASCHE HÄNGT (Spalten auf `weine`) UND KEINE EIGENE
-- QUEUE-TABELLE ENTSTEHT:
-- Die Zusage an den Nutzer lautet „nichts geht verloren" — ab dem Auslösen steht die Flasche im
-- Inventar, auch wenn sie noch namenlos ist. Damit IST der Datensatz der Warteschlangen-Eintrag.
-- Eine zweite Tabelle brächte genau die zwei Zustände hervor, die es hier nicht geben darf:
-- einen Queue-Eintrag ohne Flasche (Verarbeitung läuft für etwas, das im Inventar fehlt — der
-- Nutzer sieht seine Flasche nirgends) und eine Flasche ohne Queue-Eintrag (halb ausgefüllte Zeile,
-- die nie jemand fertig macht). Beides wäre nur mit Aufräum-Logik und Transaktionen über zwei
-- Tabellen zu verhindern. So dagegen gilt: eine Zeile, ein Zustand, gemeinsam gelöscht.
-- Nebeneffekt, der zur Fachlichkeit passt: die unfertige Flasche taucht ohne Zusatzarbeit in
-- Liste, Suche, Keller und den Kennzahlen auf — sie ist Bestand, nur noch ohne Etikettendaten.
--
-- WARUM DER DEFAULT 'fertig' IST UND NICHT 'offen':
-- Der gesamte vorhandene Bestand ist vollständig erfasst. Mit dem Default 'offen' stünde er nach
-- der Migration schlagartig komplett in der Warteschlange — der Job würde jede Flasche erneut
-- durch die kostenpflichtige KI-Kette schicken und dabei gepflegte Werte überschreiben. Ebenso
-- gilt für alles, was von Hand angelegt wird, und für die bereits installierte App (die `ki_status`
-- nicht kennt und nicht mitschickt): fertig ist der richtige Ruhezustand. 'offen' setzt einzig,
-- wer bewusst einreiht (server/wein/anreicherung.ts).
--
-- WARUM `ki_versuche` UND `ki_fehler` NEBEN DEM STATUS:
-- Ein dauerhaft unlesbares Etikett darf nicht jede Nacht Geld verbrennen — der Sammellauf gibt
-- nach drei Anläufen auf und wartet auf ein ausdrückliches „Erneut versuchen". Dafür braucht es
-- den Zähler; und `ki_fehler` sagt dem Nutzer im Klartext, WARUM die Zeile liegen bleibt,
-- statt ihn mit einem roten Abzeichen ohne Begründung stehen zu lassen.
--
-- WARUM `dublette_von` NUR MARKIERT UND NICHTS ZUSAMMENFÜHRT:
-- Zwei gleiche Flaschen sind der Normalfall (Bestand 2), ein doppelter Datensatz die Ausnahme —
-- die Maschine kann beides nicht sicher unterscheiden. Also zeigt sie den Verdacht an und der
-- Mensch entscheidet. `ON DELETE SET NULL` ist Absicht: wird der vermeintliche Zwilling gelöscht,
-- darf das Löschen NICHT scheitern (foreign_keys steht in server/db/connection.ts auf ON, und
-- das voreingestellte NO ACTION würde genau das blockieren) — der Verdacht verfällt dann einfach.
--
-- Die CHECK-Klausel steht bewusst INLINE als CHECK(spalte IN ('a','b')) mit einfachen
-- Anführungszeichen: server/db/constraints.ts parst genau diese Form aus sqlite_master und macht
-- daraus 422-Fehler bei falschen Werten sowie die `allowed`-Liste in /schema.
--
-- Additiv (ALTER TABLE ADD COLUMN, kein Table-Rebuild) — Prod trägt echte Daten. SQLite kennt kein
-- "ADD COLUMN IF NOT EXISTS", aber der Migrations-Tracker (schema_migrations) führt jede Datei
-- genau einmal aus → ein simples ALTER genügt. NOT NULL ist bei ADD COLUMN nur mit Default erlaubt
-- (haben `ki_status` und `ki_versuche`), und eine REFERENCES-Klausel nur mit Default NULL — deshalb
-- trägt `dublette_von` keinen eigenen Default.

-- ── Zustand der Hintergrund-Anreicherung (der Datensatz IST der Warteschlangen-Eintrag) ──
ALTER TABLE "weine" ADD COLUMN ki_status TEXT NOT NULL DEFAULT 'fertig'
                   CHECK(ki_status IN ('offen','laeuft','fertig','fehler'));
ALTER TABLE "weine" ADD COLUMN ki_versuche INTEGER NOT NULL DEFAULT 0;  -- Anläufe; ab 3 nur noch von Hand
ALTER TABLE "weine" ADD COLUMN ki_fehler TEXT;                          -- Klartext des letzten Fehlschlags
ALTER TABLE "weine" ADD COLUMN ki_queued_at TEXT;                       -- eingereiht/zuletzt angefasst: Reihenfolge + Stale-Rückholung

-- ── Dubletten-Verdacht: nur ein Verweis, nie eine automatische Zusammenführung ──
ALTER TABLE "weine" ADD COLUMN dublette_von INTEGER
                   REFERENCES "weine"(id) ON DELETE SET NULL;

-- Der Sammellauf holt „was ist fällig, ältestes zuerst" — genau die Spaltenreihenfolge des Index.
CREATE INDEX IF NOT EXISTS idx_weine_ki_status ON "weine"(ki_status, ki_queued_at);
