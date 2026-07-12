-- 0007_fotobox — Fotobox: strukturierte Foto-Inbox als zweiter Eingangskanal neben Telegram.
-- iOS macht eine On-Device-Vorklassifizierung (nur GÜLTIGE Domänen vorschlagen), Ole holt die
-- Queue ab, analysiert, schreibt über die v1-API in die Zielressourcen und meldet das Ergebnis zurück.
--
-- Wertebereiche (domain/intent/status/review_reason/target_resource) sind NICHT als CHECK verdrahtet,
-- sondern in fotobox_labels gepflegt → per API erweiterbar (POST /api/v1/fotobox-labels). Validierung
-- der Items läuft dynamisch gegen die aktiven Labels (server/fotobox/labels.ts).

-- ── Queue-Items ──
CREATE TABLE IF NOT EXISTS fotobox_items (
  id                     TEXT PRIMARY KEY,                     -- fbx_<ts>_<rand>
  idempotency_key        TEXT UNIQUE,                          -- doppelte Uploads → dasselbe Item
  source                 TEXT NOT NULL DEFAULT 'app_fotobox',  -- app_fotobox | telegram | api | web
  status                 TEXT NOT NULL DEFAULT 'pending',      -- validiert gegen fotobox_labels(field='status')

  -- uploaded_by
  uploaded_person        TEXT,
  uploaded_display_name  TEXT,
  uploaded_device_id     TEXT,
  uploaded_telegram_id   TEXT,

  -- routing (Vorklassifizierung)
  domain                 TEXT,                                 -- fotobox_labels(field='domain')
  intent                 TEXT,                                 -- fotobox_labels(field='intent')
  target_resource        TEXT,                                 -- fotobox_labels(field='target_resource') / v1-Ressource
  target_id              TEXT,
  confidence             REAL,
  preclassified_by       TEXT,                                 -- z.B. ios_local_ai | ocr | manual

  analysis_hint          TEXT,                                 -- JSON-Objekt (brand/category/size/status/notes/…)
  labels                 TEXT,                                 -- JSON-Array [{key,value,confidence,source}]
  telegram_equivalent    TEXT,                                 -- JSON {caption,thread_id,chat_id,message_id,media_group_id}

  -- review
  review_required        INTEGER NOT NULL DEFAULT 0,
  review_reason          TEXT,                                 -- fotobox_labels(field='review_reason')
  review_question        TEXT,

  -- processing (Claim/Lock)
  claimed_by             TEXT,
  claimed_until          TEXT,
  attempts               INTEGER NOT NULL DEFAULT 0,
  last_attempt_at        TEXT,

  -- result
  result_processed_at    TEXT,
  result_created_resource TEXT,
  result_created_id      TEXT,
  result_summary         TEXT,
  result_error           TEXT,

  created_at             TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at             TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_fotobox_items_status ON fotobox_items(status);
CREATE INDEX IF NOT EXISTS idx_fotobox_items_domain ON fotobox_items(domain);
CREATE INDEX IF NOT EXISTS idx_fotobox_items_created ON fotobox_items(created_at);

-- ── Medien je Item (Album = mehrere, stabile Reihenfolge) ──
CREATE TABLE IF NOT EXISTS fotobox_item_media (
  id                  TEXT PRIMARY KEY,                        -- med_<ts>_<rand>
  item_id             TEXT NOT NULL REFERENCES fotobox_items(id) ON DELETE CASCADE,
  storage_key         TEXT NOT NULL,                           -- fotobox/<datei> unter /data/media (via /api/v1/media/<key>)
  mime_type           TEXT,
  filename            TEXT,
  size_bytes          INTEGER,
  sha256              TEXT,
  width               INTEGER,
  height              INTEGER,
  ord                 INTEGER NOT NULL DEFAULT 1,
  created_at_original TEXT,                                    -- EXIF/Client-Aufnahmezeit
  created_at          TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_fotobox_media_item ON fotobox_item_media(item_id, ord);

-- ── Erweiterbare Wertebereiche (Enums) ──
CREATE TABLE IF NOT EXISTS fotobox_labels (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  field           TEXT NOT NULL
                    CHECK(field IN ('domain','intent','status','review_reason','target_resource','label_key')),
  value           TEXT NOT NULL,                               -- maschinenlesbarer Wert
  label           TEXT,                                        -- menschenlesbar (UI)
  target_resource TEXT,                                        -- nur bei field='domain': gemappte v1-Ressource
  description     TEXT,
  sort            INTEGER NOT NULL DEFAULT 0,
  active          INTEGER NOT NULL DEFAULT 1,
  meta            TEXT,                                        -- JSON (frei)
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at      TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(field, value)
);
CREATE INDEX IF NOT EXISTS idx_fotobox_labels_field ON fotobox_labels(field, active);

-- ── Verarbeitungs-Log (optional, Audit je Item) ──
CREATE TABLE IF NOT EXISTS fotobox_processing_log (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id  TEXT NOT NULL,
  ts       TEXT NOT NULL DEFAULT (datetime('now')),
  worker   TEXT,
  action   TEXT NOT NULL,
  detail   TEXT                                                -- JSON
);
CREATE INDEX IF NOT EXISTS idx_fotobox_proclog_item ON fotobox_processing_log(item_id, ts);

-- ── Seed: Domains (value → target_resource) ──
INSERT OR IGNORE INTO fotobox_labels (field, value, label, target_resource, sort) VALUES
  ('domain','samu_items','Samu Sachen (Kleidung/Schuhe/Spielzeug)','samu-items',10),
  ('domain','gypsi_futter','Gypsi Katzenfutter','gypsi-futter',20),
  ('domain','vorrat_lebensmittel','Vorrat / Lebensmittel','vorrat-lebensmittel',30),
  ('domain','garten_pflanze','Garten: Pflanze','garten-pflanzen',40),
  ('domain','garten_samen','Garten: Samen','garten-samen',50),
  ('domain','garten_duenger','Garten: Dünger','garten-duenger',60),
  ('domain','reiniger_produkt','Reiniger / Putzmittel','reiniger-produkte',70),
  ('domain','buecher_scan','Bücher (Cover/Regal/ISBN)','buecher',80),
  ('domain','geschenk_wunsch','Geschenkidee / Wunschliste','wunschliste-items',90),
  ('domain','reisen_doc','Reise-Dokument / Beleg','reisen-docs',100),
  ('domain','smarthome_device','Smart-Home-Gerät / Typenschild','ha-entities',110),
  ('domain','vertrag_doc','Vertrag / Rechnung','vertraege',120),
  ('domain','unknown','Unklar — Ole entscheiden lassen',NULL,999);

-- ── Seed: Intents ──
INSERT OR IGNORE INTO fotobox_labels (field, value, label, sort) VALUES
  ('intent','create','Neu erfassen',10),
  ('intent','search','Suchen',20),
  ('intent','update','Aktualisieren',30),
  ('intent','link_to_existing','An bestehenden Datensatz hängen',40),
  ('intent','mark_active','Als aktiv/in Nutzung markieren',50),
  ('intent','mark_stored','Als eingelagert markieren',60),
  ('intent','mark_out','Aussortiert/raus/verkauft',70),
  ('intent','mark_liked','Mag er (Gypsi)',80),
  ('intent','mark_disliked','Mag er nicht (Gypsi)',90),
  ('intent','list','Liste anzeigen',100),
  ('intent','mark_empty','Leer markieren',110),
  ('intent','mark_available','Wieder vorhanden',120),
  ('intent','associate','Zwei Datensätze verknüpfen',130),
  ('intent','scan','OCR/Erkennung ohne Create',140);

-- ── Seed: Statuses ──
INSERT OR IGNORE INTO fotobox_labels (field, value, label, sort) VALUES
  ('status','draft','Entwurf (noch nicht freigegeben)',10),
  ('status','pending','Bereit für Ole',20),
  ('status','processing','In Verarbeitung (gelockt)',30),
  ('status','needs_review','Rückfrage/Korrektur nötig',40),
  ('status','done','Verarbeitet',50),
  ('status','failed','Fehlgeschlagen',60),
  ('status','duplicate','Duplikat',70),
  ('status','ignored','Bewusst ignoriert',80),
  ('status','cancelled','Abgebrochen',90);

-- ── Seed: Review-Gründe ──
INSERT OR IGNORE INTO fotobox_labels (field, value, label, sort) VALUES
  ('review_reason','low_confidence','Klassifizierung unsicher',10),
  ('review_reason','ambiguous_domain','Mehrere Domänen plausibel',20),
  ('review_reason','missing_required_field','Pflichtfeld fehlt',30),
  ('review_reason','duplicate_candidate','Mögliches Duplikat',40),
  ('review_reason','no_matching_item','Kein passender Datensatz',50),
  ('review_reason','sensitive_document','Sensibles Dokument',60),
  ('review_reason','schema_validation_failed','API-Schema/allowed passt nicht',70),
  ('review_reason','media_unreadable','Bild nicht lesbar',80),
  ('review_reason','needs_user_decision','Fachliche Entscheidung nötig',90);

-- ── Seed: Target-Resources (v1-Ressourcen, in die Ole schreibt) ──
INSERT OR IGNORE INTO fotobox_labels (field, value, label, sort) VALUES
  ('target_resource','samu-items','Samu-Inventar',10),
  ('target_resource','gypsi-futter','Gypsi Futter',20),
  ('target_resource','vorrat-lebensmittel','Vorrat',30),
  ('target_resource','garten-pflanzen','Garten Pflanzen',40),
  ('target_resource','garten-samen','Garten Samen',50),
  ('target_resource','garten-duenger','Garten Dünger',60),
  ('target_resource','reiniger-produkte','Reiniger',70),
  ('target_resource','buecher','E-Book-Wunschliste',80),
  ('target_resource','elisbooks-books','Bücher (physisch)',85),
  ('target_resource','wunschliste-items','Wunschliste',90),
  ('target_resource','geschenk-geschenke','Geschenke',95),
  ('target_resource','reisen-docs','Reise-Dokumente',100),
  ('target_resource','ha-entities','Smart-Home-Entities',110),
  ('target_resource','vertraege','Verträge',120);

-- ── Seed: Label-Keys (Taxonomie für labels[].key aus On-Device-Erkennung) ──
INSERT OR IGNORE INTO fotobox_labels (field, value, label, sort) VALUES
  ('label_key','object','Objektklasse',10),
  ('label_key','text_hint','OCR-Texthinweis',20),
  ('label_key','brand','Marke',30),
  ('label_key','size','Größe',40),
  ('label_key','isbn','ISBN',50),
  ('label_key','barcode','Barcode/EAN',60),
  ('label_key','mhd','Mindesthaltbarkeit',70),
  ('label_key','color','Farbe',80);

-- Dashboard-Kachel (Web) für die Fotobox-Queue.
INSERT OR IGNORE INTO lebensbereiche (key, titel, beschreibung, emoji, gradient, api_base, sort)
VALUES ('fotobox', 'Fotobox', 'Fotos strukturiert an Ole übergeben', '📷', 'from-[#5AC8FA] via-[#007AFF] to-[#5856D6]', '/api/v1/fotobox-items', 98);
