import Foundation

// Pro-Ressource-Anzeige-Specs — erarbeitet aus dem echten DB-Schema (UI-Spec-Workflow, 2026-07-11).
// Damit sehen die Bereiche NICHT wie stumpfe Tabellen mit JSON-Rohwerten aus.

private func S(_ layout: String, _ title: String, sub: String = "", badge: String = "", hero: String = "",
               primary: [String] = [], hidden: [String] = [], fmt: [String: FieldFormat] = [:], listSub: String = "") -> DisplaySpec {
    DisplaySpec(
        layout: layout,
        titleField: title,
        subtitleField: sub.isEmpty ? nil : sub,
        badgeField: badge.isEmpty ? nil : badge,
        heroImageField: hero.isEmpty ? nil : hero,
        primaryFields: primary,
        hidden: Set(hidden),
        formats: fmt,
        listSubtitle: listSub.isEmpty ? nil : listSub
    )
}

let DISPLAY_SPECS: [String: DisplaySpec] = [
    "termine": S("event", "title", sub: "date", badge: "status",
        primary: ["date", "time", "end_date", "end_time", "location", "person", "category", "recurring", "recurring_interval", "reminder_days", "description", "notes"],
        hidden: ["reminder_sent", "cron_job_id", "source"],
        fmt: ["date": .date, "end_date": .date, "time": .time, "end_time": .time, "category": .badge, "reminder_days": .number, "description": .multiline, "notes": .multiline],
        listSub: "date"),

    "samu-items": S("photo_gallery", "name", sub: "marke", badge: "status", hero: "bild_pfade",
        primary: ["kategorie", "unterkategorie", "typ", "marke", "groesse", "altersgruppe", "zustand", "saison", "farbe", "material", "verkaufswert", "verkaufskanal", "passt_ab_groesse", "passt_ab_alter", "beschreibung", "notizen"],
        hidden: ["bild_telegram_ids", "aussortiert_am"],
        fmt: ["typ": .badge, "zustand": .badge, "saison": .badge, "verkaufswert": .price, "beschreibung": .multiline, "notizen": .multiline],
        listSub: "kategorie"),

    "samu-marken": S("entity", "name", sub: "preis_segment",
        primary: ["groessen_info", "material_fokus", "preis_segment", "herkunft", "website", "notizen"],
        hidden: ["angereichert_am"],
        fmt: ["website": .url, "groessen_info": .multiline, "notizen": .multiline],
        listSub: "herkunft"),

    "samu-bedarf": S("checklist", "beschreibung", sub: "kategorie", badge: "prioritaet",
        primary: ["kategorie", "groesse", "erledigt", "notizen"],
        hidden: ["erledigt_am"],
        fmt: ["erledigt": .bool, "notizen": .multiline],
        listSub: "kategorie"),

    "wunschliste-events": S("event", "name", sub: "date", badge: "type",
        primary: ["date", "recurring_month", "recurring_day", "erinnerungen_aktiv", "notes"],
        hidden: ["emoji", "archived"],
        fmt: ["date": .date, "recurring_month": .number, "recurring_day": .number, "erinnerungen_aktiv": .bool, "notes": .multiline],
        listSub: "date"),

    "wunschliste-items": S("generic", "title", sub: "price", badge: "status",
        primary: ["price", "category", "priority", "purchased_by", "url", "description", "ean", "price_comparison", "notes"],
        hidden: ["event_id", "image_url"],
        fmt: ["price": .price, "url": .url, "priority": .number, "description": .multiline, "price_comparison": .multiline, "notes": .multiline],
        listSub: "category"),

    "geschenk-kinder": S("person", "name", sub: "geburtsdatum",
        primary: ["profil", "negativliste", "profil_bestaetigt_am"],
        fmt: ["geburtsdatum": .date, "profil_bestaetigt_am": .date, "profil": .multiline, "negativliste": .multiline],
        listSub: "geburtsdatum"),

    "geschenk-ereignisse": S("event", "anlass", sub: "datum",
        primary: ["jahr", "alter_zum_ereignis", "erinnerungen_aktiv", "recherche_gestartet", "recherche_abgeschlossen", "profil_bestaetigung_angefragt", "profil_bestaetigt", "profil_snapshot"],
        hidden: ["kind_id"],
        fmt: ["datum": .date, "erinnerungen_aktiv": .bool, "recherche_gestartet": .bool, "recherche_abgeschlossen": .bool, "profil_bestaetigung_angefragt": .bool, "profil_bestaetigt": .bool, "profil_snapshot": .multiline],
        listSub: "datum"),

    "geschenk-geschenke": S("generic", "titel", sub: "shop", badge: "status",
        primary: ["preis", "beschreibung", "url", "bild_url", "ranking", "begruendung", "notizen", "ist_manuell"],
        hidden: ["ereignis_id", "kind_id", "quelle"],
        fmt: ["status": .badge, "preis": .price, "url": .url, "bild_url": .url, "beschreibung": .multiline, "begruendung": .multiline, "notizen": .multiline, "ranking": .number, "ist_manuell": .bool],
        listSub: "shop"),

    "geschenk-anlaesse": S("generic", "anlass",
        primary: ["aktiv", "budget_min", "budget_max"],
        hidden: ["kind_id"],
        fmt: ["aktiv": .bool, "budget_min": .price, "budget_max": .price]),

    "geschenk-vergangene": S("generic", "titel", sub: "anlass",
        primary: ["jahr", "notizen"],
        hidden: ["kind_id"],
        fmt: ["notizen": .multiline],
        listSub: "anlass"),

    "garten-pflanzen": S("photo_gallery", "name", sub: "art", badge: "status", hero: "bild_pfade",
        primary: ["art", "sorte", "standort", "bewaesserung", "beschreibung", "frostempfindlich", "min_temp", "gts_raus", "gts_rein", "notizen"],
        hidden: ["metadata"],
        fmt: ["status": .badge, "bewaesserung": .badge, "frostempfindlich": .bool, "min_temp": .number, "beschreibung": .multiline, "notizen": .multiline],
        listSub: "standort"),

    "garten-samen": S("generic", "name", sub: "sorte", hero: "bild_pfade",
        primary: ["nummer", "art", "sorte", "botanisch", "hersteller", "beschreibung", "standort_empfehlung", "pflanz_von", "pflanz_bis", "vorziehen_ab", "ernte_von", "ernte_bis", "aussaat_2_von", "aussaat_2_bis", "ernte_2_von", "ernte_2_bis", "abstand_cm", "tiefe_cm", "keimzeit_tage", "keimtemp", "keimfaehig_bis", "bio", "samenfest", "inhalt", "verwendung", "herkunft", "besonderheiten", "aktiv", "notizen"],
        hidden: ["metadata"],
        fmt: ["aktiv": .bool, "samenfest": .bool, "keimfaehig_bis": .date, "beschreibung": .multiline, "besonderheiten": .multiline, "notizen": .multiline],
        listSub: "art"),

    "garten-duenger": S("generic", "name", sub: "marke", badge: "typ", hero: "bild_pfade",
        primary: ["marke", "geeignet_fuer", "naehrstoffe", "dosierung", "intervall_wochen", "saison_von", "saison_bis", "vorraetig", "kauflink", "beschreibung", "notizen"],
        hidden: ["metadata"],
        fmt: ["typ": .badge, "vorraetig": .bool, "kauflink": .url, "beschreibung": .multiline, "notizen": .multiline],
        listSub: "marke"),

    "garten-aufgaben": S("checklist", "titel", sub: "kategorie", badge: "prioritaet",
        primary: ["kategorie", "beschreibung", "monat", "jahr", "geplant_monat", "wiederholung", "erledigt", "erledigt_am", "notizen"],
        hidden: ["pflanze_id", "samen_id", "duenger_id"],
        fmt: ["prioritaet": .badge, "erledigt": .bool, "erledigt_am": .datetime, "beschreibung": .multiline, "notizen": .multiline],
        listSub: "kategorie"),

    "garten-pflanze-duenger": S("generic", "duenger_typ_benoetigt",
        primary: ["duenger_typ_benoetigt", "empfohlen", "notizen"],
        hidden: ["pflanze_id", "duenger_id"],
        fmt: ["empfohlen": .bool, "notizen": .multiline]),

    "vorrat-lebensmittel": S("product_expiry", "name", sub: "marke", badge: "status", hero: "bild_pfad",
        primary: ["marke", "kategorie", "menge", "mhd", "restock", "verbraucht_am", "notizen"],
        fmt: ["mhd": .date, "status": .badge, "kategorie": .badge, "restock": .bool, "verbraucht_am": .date, "notizen": .multiline],
        listSub: "mhd"),

    "vorrat-rezepte": S("recipe", "titel", sub: "quelle",
        primary: ["quelle", "beschreibung", "zutaten_match", "url", "bild_url", "notizen"],
        fmt: ["url": .url, "bild_url": .url, "beschreibung": .multiline, "zutaten_match": .multiline, "notizen": .multiline],
        listSub: "quelle"),

    "gypsi-futter": S("photo_gallery", "marke", sub: "sorte", badge: "status", hero: "bild_pfad",
        primary: ["sorte", "geschmack", "notizen"],
        hidden: ["status_geaendert_am"],
        fmt: ["status": .badge, "notizen": .multiline],
        listSub: "geschmack"),

    "elisbooks-books": S("cover_card", "title", sub: "authors", hero: "thumbnail",
        primary: ["categories", "publisher", "published_date", "page_count", "language", "isbn", "is_read", "is_on_picklist", "description"],
        hidden: ["bookshelf_id"],
        fmt: ["authors": .jsonList, "categories": .jsonList, "published_date": .date, "is_read": .bool, "is_on_picklist": .bool, "description": .multiline],
        listSub: "authors"),

    "elisbooks-bookshelves": S("generic", "name", sub: "description",
        primary: ["color"],
        fmt: ["description": .multiline],
        listSub: "description"),

    "elisbooks-wishlist": S("cover_card", "title", sub: "authors", hero: "thumbnail",
        primary: ["categories", "publisher", "published_date", "page_count", "isbn", "description"],
        hidden: ["source"],
        fmt: ["authors": .jsonList, "categories": .jsonList, "published_date": .date, "description": .multiline],
        listSub: "authors"),

    "elisbooks-settings": S("generic", "setting_key",
        primary: ["setting_value"],
        fmt: ["setting_value": .multiline],
        listSub: "setting_value"),

    "ebook-wishlist": S("cover_card", "title", sub: "author", badge: "status",
        primary: ["category", "publisher", "year", "description", "isbn", "language", "cover_url", "requested_by", "requested_at", "downloaded_at", "attempts", "last_attempt", "notes", "reviews"],
        hidden: ["source_id"],
        fmt: ["status": .badge, "description": .multiline, "notes": .multiline, "reviews": .multiline, "cover_url": .url, "requested_at": .datetime, "downloaded_at": .datetime, "last_attempt": .datetime, "attempts": .number],
        listSub: "author"),

    "reiniger-produkte": S("generic", "name", sub: "marke", badge: "status", hero: "bild_pfad",
        primary: ["kategorie", "menge", "einsatzorte", "geeignet_fuer", "nicht_geeignet_fuer", "flecken", "dosierung", "pflegehinweise", "sicherheit", "restock", "quelle_url", "notizen"],
        hidden: ["meta_json", "bild_mime", "bild_sha256"],
        fmt: ["status": .badge, "restock": .bool, "quelle_url": .url, "einsatzorte": .multiline, "geeignet_fuer": .multiline, "nicht_geeignet_fuer": .multiline, "flecken": .multiline, "pflegehinweise": .multiline, "sicherheit": .multiline, "notizen": .multiline],
        listSub: "kategorie"),

    "reiniger-anwendungen": S("generic", "problem", sub: "material",
        primary: ["anleitung", "oberflaeche", "fleck_art", "anwendungsfall", "warnhinweise", "begruendung", "prioritaet"],
        hidden: ["reiniger_id"],
        fmt: ["anleitung": .multiline, "warnhinweise": .multiline, "begruendung": .multiline, "prioritaet": .number],
        listSub: "anwendungsfall"),

    "ha-entities": S("entity", "friendly_name", sub: "area_name", badge: "state",
        primary: ["domain", "area_name", "device_name", "entity_id", "disabled", "attributes"],
        hidden: ["area_id", "device_id", "last_synced", "discovered_at"],
        fmt: ["state": .badge, "disabled": .bool, "attributes": .keyValue],
        listSub: "area_name"),

    "ha-relationships": S("generic", "parent_entity_id", sub: "child_entity_id", badge: "type",
        primary: ["parent_entity_id", "child_entity_id", "auto_discovered", "manually_verified"],
        fmt: ["type": .badge, "auto_discovered": .bool, "manually_verified": .bool],
        listSub: "child_entity_id"),

    "ha-aliases": S("generic", "alias", sub: "entity_id",
        primary: ["entity_id"],
        listSub: "entity_id"),

    "ha-command-log": S("event", "input_text", sub: "action", badge: "success",
        primary: ["timestamp", "matched_entity_id", "result", "match_score", "duration_ms", "dependencies_triggered"],
        fmt: ["timestamp": .datetime, "success": .badge, "result": .multiline, "dependencies_triggered": .jsonList, "match_score": .number, "duration_ms": .number],
        listSub: "timestamp"),

    "vertraege": S("contract", "anbieter", sub: "bezeichnung", badge: "status",
        primary: ["kategorie", "kosten", "kosten_intervall", "beginn", "laufzeit_bis", "kuendigungsfrist", "verlaengerung", "kundennummer", "vertragsnummer", "notizen"],
        hidden: ["metadata"],
        fmt: ["kosten": .price, "beginn": .date, "laufzeit_bis": .date, "notizen": .multiline, "status": .badge],
        listSub: "kategorie"),

    "reisen": S("cover_card", "title", sub: "destination", badge: "status", hero: "cover_image",
        primary: ["start_date", "end_date", "country", "region", "participants", "type", "rating", "hotel", "hotel_url", "flight", "transport", "cost_total", "budget", "currency", "activities", "highlights", "tags", "booking_ref", "booking_platform", "notes", "destination_info"],
        hidden: ["source", "timezone_offset", "timezone_name"],
        fmt: ["start_date": .date, "end_date": .date, "hotel_url": .url, "cost_total": .price, "rating": .number, "notes": .multiline, "destination_info": .multiline, "status": .badge],
        listSub: "destination"),
]

/// Spec für eine Ressource, oder generischer Fallback (Titel/Untertitel geraten).
func specFor(_ resource: ResourceInfo) -> DisplaySpec {
    if let s = DISPLAY_SPECS[resource.key] { return s }
    var s = DisplaySpec(layout: "generic")
    s.heroImageField = resource.image?.col
    return s
}

func titleText(_ fields: [String: Any], _ spec: DisplaySpec) -> String {
    if let t = spec.titleField {
        let v = fieldString(fields[t]); if !v.isEmpty { return v }
    }
    return recordTitle(fields)
}

/// Ein Feld als bereits formatierter kurzer Text (für Untertitel/Listenzeile).
func formattedFieldText(_ fields: [String: Any], _ key: String?, _ spec: DisplaySpec) -> String? {
    guard let key else { return nil }
    let v = fieldString(fields[key]); if v.isEmpty { return nil }
    switch spec.formats[key] ?? guessFormat(key, fields[key]) {
    case .date: return DateText.pretty(v)
    case .datetime: return prettyDateTime(v)
    case .jsonList: return parseJSONList(v).joined(separator: ", ")
    default: return v
    }
}

func formatFor(_ fields: [String: Any], _ col: String, _ spec: DisplaySpec) -> FieldFormat {
    spec.formats[col] ?? guessFormat(col, fields[col])
}

/// Anzuzeigende Detail-Spalten: primaryFields zuerst, dann Rest — Header-/Technik-/versteckte Felder raus.
func detailColumns(_ fields: [String: Any], _ resource: ResourceInfo, _ spec: DisplaySpec) -> [String] {
    var header = Set<String>()
    for k in [spec.titleField, spec.subtitleField, spec.badgeField, spec.heroImageField, resource.image?.col] {
        if let k { header.insert(k) }
    }
    let primary = spec.primaryFields.filter { !header.contains($0) && !fieldString(fields[$0]).isEmpty }
    let primarySet = Set(primary)
    let remaining = resource.columns.filter { c in
        !primarySet.contains(c) && !header.contains(c) && !spec.hidden.contains(c)
            && !isTechnicalField(c) && !fieldString(fields[c]).isEmpty
    }
    return primary + remaining
}
