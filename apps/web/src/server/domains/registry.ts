// Registry aller API-Ressourcen. Das generische CRUD-Framework (crud.ts) bedient
// jede Ressource datengetrieben — Spalten werden zur Laufzeit aus der DB gelesen.
// Neue Ressource = ein Eintrag hier (+ Tabelle via Migration).

export interface ImageSpec {
  col: string;       // Spalte mit Bildpfad(en)
  multi: boolean;    // JSON-Array vs. Einzelwert
  area: string;      // Media-Bereich (/data/media/<area>/)
}

export interface Resource {
  key: string;        // URL-Segment: /api/v1/<key>
  table: string;      // DB-Tabelle
  domain: string;     // Gruppierung (Lebensbereich) für Capabilities/Dashboard
  label: string;
  pk?: string;        // Primärschlüssel (default "id")
  image?: ImageSpec;
  searchable?: string[]; // überschreibt Auto-Erkennung (Text-Spalten)
  sort?: string;      // Default-ORDER-BY (z.B. "created_at DESC")
  readonly?: boolean; // nur lesen
  download?: string;  // Download-URL-Präfix je {id} (z.B. Reise-Dokumente)
  actions?: { label: string; patch: Record<string, unknown> }[]; // Schnellaktionen (Status-PATCH)
}

export const RESOURCES: Resource[] = [
  // ── Termine ──
  { key: "termine", table: "termine", domain: "termine", label: "Termine", sort: "date ASC, time ASC" },
  // Generische, per-API befüllbare Erinnerungen/Ereignisse (Quelle des „Anstehendes"-Agenda-Feeds).
  // URL-Key bewusst `erinnerungen` (nicht `reminders`) — kollidiert sonst mit den statischen
  // /api/v1/reminders/due + /api/v1/reminders/[id]/sent-Routen. Tabelle bleibt `reminders`.
  { key: "erinnerungen", table: "reminders", domain: "termine", label: "Erinnerungen", sort: "date ASC, time ASC", searchable: ["title", "body", "domain", "source", "status"] },

  // ── Reisen ──
  { key: "reisen", table: "reisen_trips", domain: "reisen", label: "Reisen", image: { col: "cover_image", multi: false, area: "reisen" }, sort: "start_date DESC" },
  { key: "reisen-activities", table: "reisen_trip_activities", domain: "reisen", label: "Reise-Aktivitäten", sort: "sort_order ASC" },
  { key: "reisen-dayplans", table: "reisen_trip_day_plans", domain: "reisen", label: "Reise-Tagespläne", sort: "day_number ASC, sort_order ASC" },
  { key: "reisen-diving", table: "reisen_trip_diving", domain: "reisen", label: "Reise-Tauchen" },
  { key: "reisen-docs", table: "reisen_trip_docs", domain: "reisen", label: "Reise-Dokumente", download: "/api/v1/files/reisen-docs/" },
  { key: "reisen-emails", table: "reisen_trip_emails", domain: "reisen", label: "Reise-E-Mails" },
  { key: "reisen-emergency", table: "reisen_trip_emergency", domain: "reisen", label: "Reise-Notfallinfos", sort: "sort_order ASC" },
  { key: "reisen-flights", table: "reisen_trip_flights", domain: "reisen", label: "Reise-Flüge", sort: "sort_order ASC" },
  { key: "reisen-hotel", table: "reisen_trip_hotel", domain: "reisen", label: "Reise-Hotels" },
  { key: "reisen-links", table: "reisen_trip_links", domain: "reisen", label: "Reise-Links" },
  { key: "reisen-packing", table: "reisen_trip_packing", domain: "reisen", label: "Reise-Packliste", sort: "sort_order ASC" },
  { key: "reisen-phrases", table: "reisen_trip_phrases", domain: "reisen", label: "Reise-Sprachhilfe", sort: "sort_order ASC" },
  { key: "reisen-restaurants", table: "reisen_trip_restaurants", domain: "reisen", label: "Reise-Restaurants", sort: "sort_order ASC" },
  { key: "reisen-samu-activities", table: "reisen_trip_samu_activities", domain: "reisen", label: "Reise-Aktivitäten (Samu)", sort: "sort_order ASC" },
  { key: "reisen-weather", table: "reisen_trip_weather", domain: "reisen", label: "Reise-Wetter" },
  { key: "weekend-tips", table: "reisen_weekend_tips", domain: "reisen", label: "Wochenend-Tipps", sort: "year DESC, calendar_week DESC" },

  // ── Samu-Inventar ──
  { key: "samu-items", table: "samu_items", domain: "samu", label: "Samu Kleidung/Spielzeug", image: { col: "bild_pfade", multi: true, area: "samu" }, sort: "erfasst_am DESC", actions: [{ label: "Aussortieren", patch: { status: "aussortiert" } }, { label: "Aktiv", patch: { status: "aktiv" } }] },
  { key: "samu-marken", table: "samu_marken", domain: "samu", label: "Samu Marken", sort: "name ASC" },
  { key: "samu-bedarf", table: "samu_bedarfsliste", domain: "samu", label: "Samu Bedarfsliste" },

  // ── Wunschliste ──
  { key: "wunschliste-events", table: "wunschliste_events", domain: "wunschliste", label: "Wunschliste-Anlässe", sort: "date ASC" },
  { key: "wunschliste-items", table: "wunschliste_items", domain: "wunschliste", label: "Wunschliste-Artikel" },

  // ── Geschenkplaner ──
  { key: "geschenk-kinder", table: "geschenk_kinder", domain: "geschenkplaner", label: "Kinder", sort: "name ASC" },
  { key: "geschenk-ereignisse", table: "geschenk_ereignisse", domain: "geschenkplaner", label: "Ereignisse", sort: "datum ASC" },
  { key: "geschenk-geschenke", table: "geschenk_geschenke", domain: "geschenkplaner", label: "Geschenke", sort: "erstellt_am DESC", actions: [{ label: "Vergeben", patch: { status: "vergeben" } }, { label: "Schon geschenkt", patch: { status: "geschenkt" } }] },
  { key: "geschenk-anlaesse", table: "geschenk_anlass_config", domain: "geschenkplaner", label: "Anlass-Konfig" },
  { key: "geschenk-vergangene", table: "geschenk_vergangene_geschenke", domain: "geschenkplaner", label: "Vergangene Geschenke" },

  // ── Trauerkarten (digitalisierte Trauerkarten + Kostenübersicht, migriert aus Lovable/Supabase) ──
  { key: "trauerkarten-personen", table: "trauerkarten_personen", domain: "trauerkarten", label: "Trauerkarten-Personen", sort: "id ASC" },
  { key: "trauerkarten", table: "trauerkarten", domain: "trauerkarten", label: "Trauerkarten", image: { col: "foto_key", multi: false, area: "trauerkarten" }, searchable: ["name", "trauertext"], sort: "created_at ASC" },
  { key: "trauerkarten-kosten", table: "trauerkarten_kosten", domain: "trauerkarten", label: "Trauer-Kostenübersicht", image: { col: "beleg_key", multi: false, area: "trauerkarten" }, sort: "datum DESC" },

  // ── Garten ──
  { key: "garten-pflanzen", table: "garten_pflanzen", domain: "garten", label: "Pflanzen", image: { col: "bild_pfade", multi: true, area: "garten" }, sort: "name ASC" },
  { key: "garten-samen", table: "garten_samen", domain: "garten", label: "Samen", image: { col: "bild_pfade", multi: true, area: "garten" }, sort: "name ASC" },
  { key: "garten-duenger", table: "garten_duenger", domain: "garten", label: "Dünger", image: { col: "bild_pfade", multi: true, area: "garten" }, sort: "name ASC" },
  { key: "garten-aufgaben", table: "garten_aufgaben", domain: "garten", label: "Garten-Aufgaben", sort: "jahr ASC, monat ASC" },
  { key: "garten-pflanze-duenger", table: "garten_pflanze_duenger", domain: "garten", label: "Pflanze-Dünger-Zuordnung" },

  // ── Vorratskammer ──
  { key: "vorrat-lebensmittel", table: "vorrat_lebensmittel", domain: "vorratskammer", label: "Lebensmittel", image: { col: "bild_pfad", multi: false, area: "vorrat" }, sort: "mhd ASC" },
  { key: "vorrat-rezepte", table: "vorrat_rezepte", domain: "vorratskammer", label: "Rezepte" },

  // ── Gypsi ──
  { key: "gypsi-futter", table: "gypsi_futter", domain: "gypsi", label: "Gypsi Futter", image: { col: "bild_pfad", multi: false, area: "gypsi" }, sort: "erfasst_am DESC" },

  // ── Reiniger ──
  { key: "reiniger-produkte", table: "reiniger_produkte", domain: "reiniger", label: "Reiniger-Produkte", image: { col: "bild_pfad", multi: false, area: "reiniger" }, sort: "name ASC" },
  { key: "reiniger-anwendungen", table: "reiniger_anwendungen", domain: "reiniger", label: "Reiniger-Anwendungen" },

  // ── Bücher ──
  { key: "elisbooks-books", table: "elisbooks_books", domain: "elisbooks", label: "Bücher (physisch)", image: { col: "thumbnail", multi: false, area: "elisbooks" }, sort: "added_at DESC" },
  { key: "elisbooks-bookshelves", table: "elisbooks_bookshelves", domain: "elisbooks", label: "Bücherregale", sort: "name ASC" },
  { key: "elisbooks-wishlist", table: "elisbooks_wishlist", domain: "elisbooks", label: "Bücher-Wunschliste", image: { col: "thumbnail", multi: false, area: "elisbooks" } },
  { key: "elisbooks-settings", table: "elisbooks_user_settings", domain: "elisbooks", label: "Bücher-Einstellungen" },
  { key: "ebook-wishlist", table: "ebook_wishlist", domain: "ebooks", label: "E-Book-Wunschliste", sort: "created_at DESC" },

  // ── Smart Home ──
  { key: "ha-entities", table: "ha_entities", domain: "smarthome", label: "HA Entities", sort: "friendly_name ASC" },
  { key: "ha-relationships", table: "ha_relationships", domain: "smarthome", label: "HA Beziehungen" },
  { key: "ha-aliases", table: "ha_aliases", domain: "smarthome", label: "HA Aliase" },
  { key: "ha-command-log", table: "ha_command_log", domain: "smarthome", label: "HA Kommando-Log", sort: "timestamp DESC" },

  // ── Verträge ──
  { key: "vertraege", table: "vertraege", domain: "vertraege", label: "Verträge", sort: "kategorie ASC" },

  // ── Foto-Eingang (Upload → Agent kategorisiert) ──
  { key: "foto-inbox", table: "foto_inbox", domain: "foto", label: "Foto-Eingang", image: { col: "storage_key", multi: false, area: "foto-inbox" }, sort: "id DESC", searchable: ["bereich", "notiz", "status", "zugeordnet_resource"] },

  // ── Fotobox (strukturierte Foto-Queue; eigene Lifecycle-Routen überschreiben das generische CRUD) ──
  { key: "fotobox-items", table: "fotobox_items", domain: "fotobox", label: "Fotobox-Items", sort: "created_at DESC", searchable: ["status", "domain", "intent", "target_resource", "uploaded_person", "result_summary"] },
  // Erweiterbare Wertebereiche (Enums) — neue Labels via generischem POST /api/v1/fotobox-labels.
  { key: "fotobox-labels", table: "fotobox_labels", domain: "fotobox", label: "Fotobox-Labels", sort: "field ASC, sort ASC, value ASC", searchable: ["field", "value", "label"] },
  // Verarbeitungs-Log je Item (nur lesen; Writes intern über die Lifecycle-Routen).
  { key: "fotobox-processing-log", table: "fotobox_processing_log", domain: "fotobox", label: "Fotobox-Verarbeitungs-Log", sort: "ts DESC", readonly: true },

  // ── Abfuhrkalender (Müll-Abfuhrtermine) ──
  { key: "abfuhr-termine", table: "abfuhr_termine", domain: "abfuhrkalender", label: "Abfuhrtermine", sort: "datum ASC", searchable: ["kategorie", "summary"] },

  // ── System: Lebensbereiche-Registry (Dashboard-Steuerung) ──
  { key: "lebensbereiche", table: "lebensbereiche", domain: "system", label: "Lebensbereiche", sort: "sort ASC" },
];

const BY_KEY = new Map(RESOURCES.map((r) => [r.key, r]));
export const resourceByKey = (key: string): Resource | undefined => BY_KEY.get(key);
export const pkOf = (r: Resource): string => r.pk ?? "id";
