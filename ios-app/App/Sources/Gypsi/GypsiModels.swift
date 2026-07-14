import SwiftUI

// Native Gypsi-Katzenfutter-Modelle. Backend = Kompat-API `/api/gypsi/futter`
// (bare Array, snake_case, deutsche Keys). Jedes Futter ist entweder `mag_er` oder
// `mag_er_nicht_mehr`. Bild: `bild_pfad` (EINZELner Storage-Key, kein JSON-Array).

// MARK: - Futter

struct GypsiFutter: Identifiable, Equatable {
    let id: Int
    var marke: String            // NOT NULL
    var sorte: String            // NOT NULL
    var geschmack: String?
    var bildPfad: String?        // einzelner Storage-Key (ggf. mit `images/`-Prefix)
    var status: String           // mag_er | mag_er_nicht_mehr
    var erfasstAm: String?       // "yyyy-MM-dd HH:mm:ss" (UTC)
    var statusGeaendertAm: String?
    var notizen: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        marke = Coerce.str(f["marke"]) ?? ""
        sorte = Coerce.str(f["sorte"]) ?? ""
        geschmack = Coerce.str(f["geschmack"])
        bildPfad = Coerce.str(f["bild_pfad"])
        status = Coerce.str(f["status"]) ?? "mag_er"
        erfasstAm = Coerce.str(f["erfasst_am"])
        statusGeaendertAm = Coerce.str(f["status_geaendert_am"])
        notizen = Coerce.str(f["notizen"])
    }

    var liked: Bool { status == "mag_er" }
    /// Einzelnes Bild → auth-fähiger Media-Pfad (entfernt defensiv das `images/`-Prefix).
    var imagePath: String? { mediaURLPath(fromKey: bildPfad ?? "") }
}

// MARK: - Statusfilter (Segment)

enum GypsiStatusFilter: String, CaseIterable, Hashable {
    case alle
    case mag_er
    case mag_er_nicht_mehr

    var label: String {
        switch self {
        case .alle: return "🐱 Alles"
        case .mag_er: return "✓ Mag er"
        case .mag_er_nicht_mehr: return "✗ Mag er nicht mehr"
        }
    }

    var color: Color {
        switch self {
        case .alle: return GypsiStyle.amber
        case .mag_er: return GypsiStyle.greenFill
        case .mag_er_nicht_mehr: return GypsiStyle.redFill
        }
    }
}

// MARK: - Visuelle Konfiguration

enum GypsiStyle {
    // Warmes Amber/Orange-Thema (1:1 zur PWA).
    static let amber = Color(hex: "F59E0B")       // amber-500
    static let green = Color(hex: "16A34A")       // green-600 (Badge-Text)
    static let greenFill = Color(hex: "22C55E")   // green-500 (gefüllte Fläche)
    static let red = Color(hex: "DC2626")         // red-600 (Badge-Text)
    static let redFill = Color(hex: "EF4444")     // red-500 (gefüllte Fläche)

    struct StatusInfo {
        let badge: String        // Statusbadge auf der Karte
        let badgeColor: Color
        let toggleLabel: String  // Beschriftung des Umschaltknopfs
        let toggleColor: Color   // Farbe des Umschaltknopfs (führt zum Gegen-Status)
        let borderColor: Color
    }

    static func info(_ status: String) -> StatusInfo {
        if status == "mag_er_nicht_mehr" {
            return StatusInfo(
                badge: "✗ Mag er nicht mehr", badgeColor: red,
                toggleLabel: "👍 Mag er wieder", toggleColor: greenFill,
                borderColor: redFill)
        }
        return StatusInfo(
            badge: "✓ Mag er", badgeColor: green,
            toggleLabel: "👎 Mag er nicht mehr", toggleColor: redFill,
            borderColor: amber)
    }
}

// MARK: - Datum

/// Kurzes Datum `dd.MM.yyyy` aus dem UTC-Timestamp (`"yyyy-MM-dd HH:mm:ss"`).
enum GypsiDate {
    private static let parse: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    private static let out: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "dd.MM.yyyy"; f.locale = Locale(identifier: "de_DE"); return f
    }()
    static func short(_ s: String?) -> String? {
        guard let s, let d = parse.date(from: String(s.prefix(10))) else { return nil }
        return out.string(from: d)
    }
}
