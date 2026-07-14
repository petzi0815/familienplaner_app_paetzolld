-- 0012_trauerkarten.sql — Lebensbereich "Trauerkarten" (Migration aus Lovable/Supabase memories-app)
-- Digitalisierte Trauerkarten (Absender/Text/Geldbetrag/Foto) + Kostenuebersicht (Einnahmen/Ausgaben,
-- Belege, Personen-Aufteilung). Bestandsdaten 1:1 aus Supabase-Projekt tbuifjuhurenwcwjxoaz uebernommen.

CREATE TABLE IF NOT EXISTS "trauerkarten_personen" (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS "trauerkarten" (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  trauertext TEXT,
  geldbetrag REAL DEFAULT 0,
  foto_key TEXT,
  person_id INTEGER REFERENCES "trauerkarten_personen"(id) ON DELETE SET NULL,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_trauerkarten_person ON "trauerkarten"(person_id);

CREATE TABLE IF NOT EXISTS "trauerkarten_kosten" (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  beschreibung TEXT NOT NULL,
  betrag REAL NOT NULL DEFAULT 0,
  ist_einnahme INTEGER NOT NULL DEFAULT 0,
  datum TEXT,
  beleg_key TEXT,
  person_id INTEGER REFERENCES "trauerkarten_personen"(id) ON DELETE SET NULL,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_trauerkarten_kosten_person ON "trauerkarten_kosten"(person_id);

-- Registry-Eintrag fuer Portal/Capabilities (nativer iOS-Bereich routet ueber BEREICH_REGISTRY).
INSERT OR IGNORE INTO lebensbereiche (key, titel, emoji, gradient, sort, enabled)
VALUES ('trauerkarten', 'Trauerkarten', '🕊️', 'from-[#64748B] via-[#475569] to-[#334155]', 13, 1);

-- Personen
INSERT OR IGNORE INTO "trauerkarten_personen" (id,name) VALUES (1, 'Elita');
INSERT OR IGNORE INTO "trauerkarten_personen" (id,name) VALUES (2, 'Andre');
INSERT OR IGNORE INTO "trauerkarten_personen" (id,name) VALUES (3, 'Maggie');

-- Trauerkarten
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (1, 'Familie Kruse', '', 100, 'trauerkarten/karte-1.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (2, 'Erna', 'Herzliches Beileid', 10, 'trauerkarten/karte-2.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (3, 'Viktor und Lili Graf', 'Herzliches Beileid von Fa. Viktor und Lili Graf', 50, 'trauerkarten/karte-3.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (4, 'Familie Graf aus Daulsen', 'Unser herzliches Beileid', 50, 'trauerkarten/karte-4.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (5, 'Marina, Viktor und Kinder', 'Jedes Wort ist zuviel und doch zu wenig. Wir wünschen euch alle Kraft der Welt, um diesen Verlust zu tragen. Wir hoffen, dass alle gemeinsamen Erinnerungen euch ein wenig trösten können und durch die schwere Zeit helfen. Wir sind in Gedanken bei euch.', 100, 'trauerkarten/karte-5.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (6, 'Wilfried Wegläuft', 'Dem immer netten Honda-Doktor Waldemar werde ich immer in Ehren verbunden bleiben. Alles hat seine Zeit.', 0, 'trauerkarten/karte-6.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (7, 'Maria, Alexander', 'In stiller Trauer "was man tief in seinem Herzen besitzt, kann man durch den Tod nicht verlieren" Unser herzliches Beileid.', 50, 'trauerkarten/karte-7.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (8, 'Familie Befuss', 'Liebe Trauerfamilie, wir sprechen Euch allen unser herzliches Beileid aus. Wir trauern mit Euch, in dieser schmerzlichen Zeit des Abschieds wünschen wir Euch allen ganz viel Kraft!', 50, 'trauerkarten/karte-8.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (9, 'Fam. Dai', 'Wir möchten euch in dieser Zeit unser tief empfundenes Mitgefühl aussprechen und wünschen euch von ganzem Herzen viel Kraft Trost und Stärke in diesen schweren Zeiten.', 50, 'trauerkarten/karte-9.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (10, 'Harmel', '', 20, 'trauerkarten/karte-10.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (11, 'Familie Kitsch+ Anika Weede', 'Liebe Familie Stöke, die Nachricht, dass Waldewart verstorben ist, hat uns sehr betrübt. Wir haben Waldewart als liebenswerten Menschen kennen lernen dürfen und sind dankbar, dass er unser sehr freundlicher und guter Nachbar war. Vor allem Kinder und meine Wenigkeit müssen aufrichtiges Beileid ausdrücken.', 30, 'trauerkarten/karte-11.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (12, 'Maria Neb', 'Liebe Angehörige Fa. Stieke, mein herzliches Beileid an euch alle.', 20, 'trauerkarten/karte-12.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (13, 'Familie Abt, Andrej, Natalie, Vitalij, Veronika, Daniel und Julia', 'Liebe Familie Stihke, Jedes Wort ist zu viel, und doch zu wenig. Wir wünschen euch alle Kraft der Welt, um diesen schweren Verlust zu tragen. Wir hoffen, dass ihr dennoch Trost in den vielen wundervollen Erinnerungen finden könnt. In liebevoller Verbundenheit', 50, 'trauerkarten/karte-13.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (14, 'Alexander & Elena Kruse', 'Eine Stimme, die vertraut war schweigt. Ein Mensch, der immer da war, ist nicht mehr. Was bleibt, sind dankbare Erinnerungen, die niemand nehmen kann. In stiller Trauer', 0, 'trauerkarten/karte-14.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (15, 'Fam. Kruse', 'In tiefem Mitgefühl begleiten Sie unsere Gedanken in diesen schweren Stunden.', 40, 'trauerkarten/karte-15.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (16, 'Fam. Frank', 'Unser herzliches und aufrichtiges Beileid zu Eurem schweren Verlust! Kraft, Liebe und Zuversicht sollen Euch jetzt begleiten. In aufrichtiger Anteilnahme', 40, 'trauerkarten/karte-16.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (17, 'Fam. Alexander & Elvira mit Kindern', 'Es ist schwer einen geliebten Menschen für immer gehen zu lassen - wir möchten Euch und Euren Familien unser herzliches Beileid aussprechen. Möge Euch in dieser schweren, traurigen Zeit die Erinnerungen an die glücklichen Stunden und das gemeinsam Erlebte Kraft, Mut und Zuversicht spenden.', 50, 'trauerkarten/karte-17.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (18, 'Anna und Waldemar Dering', 'In stiller Anteilnahme. Unser herzliches Beileid und viel Kraft für die kommende Zeit. Möge Gott euch Trost schenken in dieser schweren Zeit.', 50, 'trauerkarten/karte-18.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (19, 'R. M. Graf', '', 50, 'trauerkarten/karte-19.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (20, 'Erna Marlanov', '', 25, 'trauerkarten/karte-20.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (21, 'Natascha', '', 10, 'trauerkarten/karte-21.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (22, 'Lidia Wagner, Rosa und Georg Klein', 'In dieser schweren Zeit möchten wir unser tief empfundenes Mitgefühl aussprechen. Wir wünschen euch viel Kraft, Zusammenhalt und liebe Menschen, die euch zur Seite stehen. In stiller Anteilnahme', 100, 'trauerkarten/karte-22.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (23, 'Ulrich, Ulla und Malte Schultze', 'Liebe Hinterbliebende, es ist schwer tröstende Worte zu finden, aber wir möchten Ihnen unser tiefes Mitgefühl für Ihren schweren Verlust mitteilen. Wir werden Ihren Vater immer als lieben und hilfsbereiten Nachbarn in Erinnerung behalten!', 0, 'trauerkarten/karte-23.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (24, 'Helene', 'Liebe Maggie, liebe Elita! Ich bin in Gedanken jetzt bei euch und wünsche euch von ganzem Herzen viel Kraft. In stiller Anteilnahme', 50, 'trauerkarten/karte-24.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (25, 'Viola u. Tomek mit Romeo', 'Liebe Trauerfamilie, hiermit möchten wir Euch unser aufrichtiges Mitgefühl und tiefe Anteilnahme bekunden. Wir wünschen Euch viel Kraft in dieser schweren Zeit! Unser herzliches Beileid...', 100, 'trauerkarten/karte-25.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (26, 'Johann, Rimma', 'Mit dem Tod eines geliebten Menschen verliert man vieles, niemals aber die gemeinsam verbrachte Zeit.', 50, 'trauerkarten/karte-26.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (27, 'Alexander Hammerschmidt', 'Ich möchte euch mein herzliches Mitgefühl ausdrücken und viel Kraft und Trost wünschen.', 150, 'trauerkarten/karte-27.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (28, 'Thomas und Birgit Kümmermann', 'Sehr geehrte Familie Stülke, mit Bestürzung haben wir vom Tod Ihres lieben Vaters erfahren. Wir möchten Ihnen unser aufrichtiges Beileid aussprechen. Wir haben Ihren Vater als ruhigen hilfsbereiten Nachbarn kennen gelernt. In stiller Anteilnahme', 0, 'trauerkarten/karte-28.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten" (id,name,trauertext,geldbetrag,foto_key,person_id) VALUES (29, 'Uli Schmitz und Mitarbeiter', 'Herzliche Anteilnahme', 0, 'trauerkarten/karte-29.jpg', 1);

-- Kostenuebersicht
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (1, 'Bargeldbestand in Wohnung gefunden', 1750, 1, '2025-06-12', NULL, 1);
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (2, 'Barmer Zuzahlung pflege', 40, 0, '2025-06-12', NULL, 1);
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (3, 'Blumen', 1050, 0, '2025-06-19', NULL, 1);
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (4, 'Publicare Rechnung', 10, 0, '2025-06-19', NULL, 1);
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (5, 'Blumen zum Streuen', 20, 0, '2025-06-20', NULL, 3);
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (6, 'Lydia Blumen', 200, 1, '2025-06-23', NULL, 1);
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (7, 'Olga blumen', 200, 1, '2025-06-24', NULL, 1);
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (8, 'UVH Weser Aller Wasser', 11.25, 0, '2025-06-24', 'trauerkarten/beleg-8.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (9, 'Brieftasche papa', 20, 1, '2025-06-24', NULL, 1);
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (10, 'Kündigung DMB Rechtsschutz via Aboalarm', 8.99, 0, '2025-06-24', 'trauerkarten/beleg-10.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (11, 'Genusswerkstatt', 2450, 0, '2025-06-26', NULL, 1);
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (12, 'Katja Blumen', 75, 1, '2025-06-29', NULL, 1);
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (13, 'Nösel Beerdigung', 3834.42, 0, '2025-06-30', 'trauerkarten/beleg-13.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (14, 'Kfz steuer', 85.5, 0, '2025-07-03', 'trauerkarten/beleg-14.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (15, 'Porto Karten', 36.95, 0, '2025-07-04', 'trauerkarten/beleg-15.jpg', 3);
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (16, 'Druck Karten', 35.2, 0, '2025-07-04', 'trauerkarten/beleg-16.jpg', 3);
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (17, 'Papier Trauerhüllen', 21.3, 0, '2025-07-04', 'trauerkarten/beleg-17.jpg', 3);
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (18, 'Kühlkammer', 130, 0, '2025-07-19', 'trauerkarten/beleg-18.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (19, 'Publicare', 10, 0, '2025-07-21', 'trauerkarten/beleg-19.jpg', 1);
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (20, 'Konotauflösung ING', 23213.3, 1, '2025-07-31', NULL, 1);
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (21, 'Wasserverband', 47.3, 0, '2025-08-25', 'trauerkarten/beleg-21.jpg', NULL);
INSERT OR IGNORE INTO "trauerkarten_kosten" (id,beschreibung,betrag,ist_einnahme,datum,beleg_key,person_id) VALUES (22, 'KFZ Steuer Erstattung', 79, 1, '2025-09-07', NULL, NULL);
