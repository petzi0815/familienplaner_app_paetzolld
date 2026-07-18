import Foundation

/// Deterministische Fixtures für den UI-Test-Modus. Im `-uitest`-Lauf liefert der `CompatClient` für
/// bestimmte Pfade diese Daten (statt das nicht erreichbare Test-Backend zu treffen). Damit werden
/// DATENGETRIEBENE UI-Tests möglich (z.B. Geschenkplaner: Event antippen → Detail öffnet sich +
/// Jahr wird korrekt „2026" statt „2.026" gerendert). Best Practice: reproduzierbare Fixtures statt
/// echtem Backend → der UI-Test findet Navigations-/Render-Bugs zuverlässig und ohne Netz/Secret.
enum UITestFixtures {
    /// Objekt-Antwort (Dashboard, Einzel-GET) für einen Pfad — nil = keine Fixture (normaler Netzweg).
    static func object(_ path: String) -> [String: Any]? {
        guard UITestMode.isActive else { return nil }
        switch path {
        case "/geschenkplaner/dashboard": return dashboard
        case "/geschenkplaner/ereignisse/1": return ereignis1
        case "/buecher/search": return shelfmarkSearch
        case "/buecher/calibre/shelves": return calibreShelves
        case "/buecher/calibre/books": return calibreBooks
        case "/buecher/calibre/book/5356": return calibreBookDetail
        default: return nil
        }
    }

    // ── v1-JSON-Fixtures (vom APIClient im -uitest-Modus genutzt) ──
    static var dashboardData: Data? {
        guard UITestMode.isActive else { return nil }
        return try? JSONSerialization.data(withJSONObject: dashboardToday)
    }
    static var feedSubscribeData: Data? {
        guard UITestMode.isActive else { return nil }
        return try? JSONSerialization.data(withJSONObject: ["url": "https://example.test/api/feed/uitest/familienplaner.ics", "webcal": "webcal://example.test/api/feed/uitest/familienplaner.ics"])
    }
    static var appVersionData: Data? {
        guard UITestMode.isActive else { return nil }
        return try? JSONSerialization.data(withJSONObject: ["latest_build": 999, "testflight_url": "itms-beta://"])
    }
    /// Alarmo-Status (unscharf, erreichbar) → die Alarmanlage-Kachel zeigt das „Aktivieren"-Menü.
    static var alarmoData: Data? {
        guard UITestMode.isActive else { return nil }
        return try? JSONSerialization.data(withJSONObject: [
            "configured": true, "reachable": true, "state": "disarmed",
            "arm_mode": NSNull(), "next_state": "disarmed", "changed_by": "UITest",
            "friendly_name": "Alarmo", "open_sensors": NSNull(),
        ])
    }
    /// Haus-Steuerung (Smart-Home-Tab): 2 Raffstores + 3 Szenen.
    static var houseData: Data? {
        guard UITestMode.isActive else { return nil }
        return try? JSONSerialization.data(withJSONObject: [
            "configured": true,
            "covers": [
                ["entity": "cover.raffstore_kueche_invert", "name": "Küche", "reachable": true, "state": "open", "position": 100, "tilt": 61],
                ["entity": "cover.raffstore_fernseher_invert", "name": "TV", "reachable": true, "state": "closed", "position": 0, "tilt": 61],
            ],
            "scripts": [
                ["entity": "script.raffstore_putzen", "name": "Putzen", "icon": "sparkles"],
                ["entity": "script.raffstore_verdunkeln", "name": "Dunkel", "icon": "moon.fill"],
                ["entity": "script.raffstore_sichtschutz", "name": "Sicht", "icon": "eye.slash.fill"],
            ],
        ])
    }
    /// Kameraliste (Smart-Home-Tab): 2 Kameras (Snapshots/Streams treffen im Test kein Backend → Platzhalter).
    static var camerasData: Data? {
        guard UITestMode.isActive else { return nil }
        return try? JSONSerialization.data(withJSONObject: [
            "configured": true,
            "cameras": [
                ["entity": "camera.einfahrt_high", "name": "Einfahrt"],
                ["entity": "camera.wohnzimmer_high", "name": "Wohnzimmer"],
            ],
        ])
    }

    /// Bare-Array-Antwort für einen Pfad.
    static func array(_ path: String) -> [[String: Any]]? {
        guard UITestMode.isActive else { return nil }
        switch path {
        case "/geschenkplaner/kinder": return kinder
        default: return nil
        }
    }

    // ── Geschenkplaner ──
    // Zukünftiges Datum (immer „anstehend"), aber jahr=2026 zum Testen der Jahres-Formatierung.
    private static let dashboard: [String: Any] = [
        "anstehende": [ereignis1Summary],
        "offene_bestaetigung": [],
        "stats": ["kinder": 1, "anstehende_ereignisse": 1],
    ]

    private static let ereignis1Summary: [String: Any] = [
        "id": 1, "kind_id": 1, "kind_name": "Testkind", "anlass": "geburtstag",
        "datum": "2099-09-09", "jahr": 2026, "alter_zum_ereignis": 5,
        "geschenke_count": 2, "geschenke_ausgaben": 20.0,
        "geschenke_status": ["vorschlag": 1, "ausgewaehlt": 1],
        "budget_min": 20, "budget_max": 60, "erinnerungen_aktiv": 1,
    ]

    private static let ereignis1: [String: Any] = [
        "id": 1, "kind_id": 1, "kind_name": "Testkind", "anlass": "geburtstag",
        "datum": "2099-09-09", "jahr": 2026, "budget_min": 20, "budget_max": 60,
        "erinnerungen_aktiv": 1, "profil_bestaetigung_angefragt": 0, "profil_bestaetigt": 1,
        "geschenke": [
            ["id": 10, "kind_id": 1, "ereignis_id": 1, "titel": "Test-Geschenk A", "status": "vorschlag", "ranking": 2, "preis": 20.0],
            ["id": 11, "kind_id": 1, "ereignis_id": 1, "titel": "Test-Geschenk B", "status": "ausgewaehlt", "ranking": 0, "preis": 15.0],
        ],
    ]

    private static let kinder: [[String: Any]] = [
        ["id": 1, "name": "Testkind", "geburtsdatum": "2020-09-09",
         "anlaesse": [["id": 1, "kind_id": 1, "anlass": "geburtstag", "aktiv": 1, "budget_min": 20, "budget_max": 60]],
         "naechste_ereignisse": [ereignis1Summary]],
    ]

    // ── Home-Dashboard (KPI-Kacheln + Agenda) ──
    private static let dashboardToday: [String: Any] = [
        "date": "2026-07-14",
        "kpis": [
            ["key": "foto", "icon": "tray.full.fill", "label": "Neue Fotos", "value": 2, "domain": "foto", "target": "inbox"],
            ["key": "termine", "icon": "calendar", "label": "Anstehende Termine", "value": 3, "domain": "termine", "target": "bereich:termine"],
            ["key": "reminders", "icon": "bell.badge.fill", "label": "Erinnerungen", "value": 1, "domain": "termine", "target": "heute"],
            ["key": "vorrat", "icon": "clock.badge.exclamationmark", "label": "Bald ablaufend", "value": 4, "domain": "vorratskammer", "target": "bereich:vorratskammer"],
            ["key": "nachkaufen", "icon": "cart.fill", "label": "Nachkaufen", "value": 5, "domain": "reiniger", "target": "bereich:reiniger"],
            ["key": "geschenke", "icon": "gift.fill", "label": "Geschenk-Anlässe", "value": 2, "domain": "geschenkplaner", "target": "bereich:geschenkplaner"],
        ],
        "agenda": [
            ["source": "termin", "domain": "termine", "id": "termin-1", "ref_id": 1, "title": "UITEST Zahnarzt", "subtitle": "Samu", "location": "Dr. Test, Musterstraße 1, Hannover", "date": "2099-09-09", "time": "10:00", "days_until": 9999, "read": false, "notify": false],
            ["source": "abfuhr", "domain": "abfuhrkalender", "id": "abfuhr-1", "ref_id": 1, "title": "🗑️ Restmüll", "date": "2099-09-10", "days_until": 9999],
            ["source": "reminder", "domain": "termine", "id": "reminder-1", "ref_id": 1, "title": "UITEST Erinnerung", "subtitle": "per API", "date": "2099-09-11", "days_until": 9999],
        ],
        "aufgaben": [
            ["source": "aufgabe", "domain": "aufgaben", "id": "aufgabe-1", "ref_id": 1, "title": "UITEST Steuer", "description": "Unterlagen sortieren", "owner": "lars", "due_date": "2020-01-01", "days_until": -9999, "overdue": true, "status": "offen", "priority": "hoch", "recurring": "einmalig", "project": "Finanzen", "termin_id": NSNull()],
            ["source": "aufgabe", "domain": "aufgaben", "id": "aufgabe-2", "ref_id": 2, "title": "UITEST Blumen giessen", "description": "Balkon Ostseite", "owner": "elita", "due_date": NSNull(), "days_until": NSNull(), "overdue": false, "status": "offen", "priority": "normal", "recurring": "woechentlich", "project": NSNull(), "termin_id": NSNull()],
            ["source": "garten", "domain": "garten", "id": "garten-1", "ref_id": 5, "title": "UITEST Rasen mähen", "description": "Vorgarten", "owner": NSNull(), "due_date": NSNull(), "due_label": "Juli 2026", "days_until": NSNull(), "overdue": false, "status": "offen", "priority": "normal", "recurring": "jaehrlich", "project": "Garten", "termin_id": NSNull()],
        ],
        "aufgaben_erledigt": [
            ["source": "aufgabe", "domain": "aufgaben", "id": "aufgabe-9", "ref_id": 9, "title": "UITEST Erledigt Paket", "description": "abgeholt", "owner": "elita", "due_date": NSNull(), "days_until": NSNull(), "overdue": false, "status": "erledigt", "priority": "normal", "recurring": "einmalig", "project": NSNull(), "termin_id": NSNull(), "done_at": "2026-07-17 10:00:00"],
        ],
        "termine_upcoming": [],
        "reminders_due": 1,
        "next_trip": NSNull(),
        "garten_offen": 0,
        "vorrat_bald_ablaufend": [
            ["id": 1, "name": "UITEST Joghurt", "mhd": "2026-07-20", "kategorie": "kuehlschrank", "bild_pfad": NSNull()],
            ["id": 2, "name": "UITEST Hack", "mhd": "2026-07-19", "kategorie": "gefrierfach", "bild_pfad": NSNull()],
        ],
        "abfuhr_next": [],
        "counts": ["samu_items": 0, "geschenke_offen": 6, "buecher": 0, "vertraege": 0, "foto_inbox_neu": 2],
    ]

    // ── Calibre-Web (Bibliothek) ──
    private static let calibreShelves: [String: Any] = [
        "shelves": [["id": 2, "name": "To Do"], ["id": 3, "name": "Lars"], ["id": 8, "name": "Romane"]],
    ]
    private static let calibreBooks: [String: Any] = [
        "total": 2,
        "rows": [
            ["id": 5356, "title": "UITEST Bibliotheksbuch", "authors": "Test Autor", "has_cover": false, "tags": [], "series": NSNull(), "isbn": NSNull(), "read_status": false, "description": "Eine Testbeschreibung.", "publisher": "Test Verlag", "published": "2024", "languages": "Deutsch"],
            ["id": 5355, "title": "Zweites Testbuch", "authors": "Andere Autorin", "has_cover": false, "tags": [], "series": NSNull(), "isbn": NSNull(), "read_status": false],
        ],
    ]
    private static let calibreBookDetail: [String: Any] = [
        "shelf_ids": [2],
        "formats": ["epub"],
        "book": ["id": 5356, "title": "UITEST Bibliotheksbuch", "authors": "Test Autor", "has_cover": false, "tags": ["Roman"], "series": NSNull(), "isbn": "9781234567890", "read_status": false, "description": "Eine ausführliche Testbeschreibung des Buches.", "publisher": "Test Verlag", "published": "2024", "languages": "Deutsch", "rating": NSNull()],
    ]

    // ── Externe Buchsuche (Shelfmark) ──
    private static let shelfmarkSearch: [String: Any] = [
        "query": "test",
        "count": 1,
        "results": [
            ["source_id": "sm1", "title": "UITEST Testbuch", "format": "epub", "size": "1.2MB",
             "author": "Test Autor", "language": "de", "year": "2024",
             "_raw": ["source_id": "sm1", "title": "UITEST Testbuch", "format": "epub", "source": "direct_download"]],
        ],
    ]
}
