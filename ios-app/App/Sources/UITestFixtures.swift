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
        default: return nil
        }
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
}
