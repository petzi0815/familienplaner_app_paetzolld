import SwiftUI

// Native Samu-Inventar-Modelle. Backend = Kompat-API `/api/items`, `/api/marken`, `/api/bedarf`
// (bare Arrays, snake_case, Booleans als 0/1). Bilder: `bild_pfade` (JSON-Array von Storage-Keys).

// MARK: - Item (Kleidung/Spielzeug)

struct SamuItem: Identifiable, Equatable {
    let id: Int
    var typ: String?            // kleidung | spielzeug
    var kategorie: String?
    var unterkategorie: String?
    var name: String?
    var marke: String?
    var beschreibung: String?
    var groesse: String?
    var zustand: String?        // neu | sehr_gut | gut | gebraucht
    var verkaufswert: Double?
    var farbe: String?
    var saison: String?
    var material: String?
    var status: String          // aktiv | eingelagert | aussortiert | verkauft
    var bildPfade: [String]     // Storage-Keys
    var notizen: String?
    var erfasstAm: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        typ = Coerce.str(f["typ"])
        kategorie = Coerce.str(f["kategorie"])
        unterkategorie = Coerce.str(f["unterkategorie"])
        name = Coerce.str(f["name"])
        marke = Coerce.str(f["marke"])
        beschreibung = Coerce.str(f["beschreibung"])
        groesse = Coerce.str(f["groesse"])
        zustand = Coerce.str(f["zustand"])
        verkaufswert = Coerce.double(f["verkaufswert"])
        farbe = Coerce.str(f["farbe"])
        saison = Coerce.str(f["saison"])
        material = Coerce.str(f["material"])
        status = Coerce.str(f["status"]) ?? "aktiv"
        bildPfade = Coerce.stringArray(f["bild_pfade"])
        notizen = Coerce.str(f["notizen"])
        erfasstAm = Coerce.str(f["erfasst_am"])
    }

    var displayTitle: String { marke ?? name ?? "Unbenannt" }
    var typEmoji: String { typ == "spielzeug" ? "🧸" : "👕" }
    var imagePath: String? { mediaURLPath(fromKey: bildPfade.first ?? "") }
    var imagePaths: [String] { bildPfade.compactMap { mediaURLPath(fromKey: $0) } }
    var hasMarke: Bool { (marke?.isEmpty == false) }
}

// MARK: - Marke

struct SamuMarke: Identifiable, Equatable {
    let id: Int
    var name: String
    var groessenInfo: String?
    var herkunft: String?
    var materialFokus: String?
    var website: String?
    var preisSegment: String?
    var notizen: String?
    var angereichertAm: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        name = Coerce.str(f["name"]) ?? "Marke"
        groessenInfo = Coerce.str(f["groessen_info"])
        herkunft = Coerce.str(f["herkunft"])
        materialFokus = Coerce.str(f["material_fokus"])
        website = Coerce.str(f["website"])
        preisSegment = Coerce.str(f["preis_segment"])
        notizen = Coerce.str(f["notizen"])
        angereichertAm = Coerce.str(f["angereichert_am"])
    }

    /// Website mit https-Prefix, falls schemalos.
    var websiteURL: URL? {
        guard let w = website, !w.isEmpty else { return nil }
        return URL(string: w.hasPrefix("http") ? w : "https://\(w)")
    }
}

// MARK: - Bedarf (Einkaufsliste)

struct SamuBedarf: Identifiable, Equatable {
    let id: Int
    var beschreibung: String
    var kategorie: String?
    var groesse: String?
    var prioritaet: String      // hoch | normal | niedrig
    var notizen: String?
    var erledigt: Bool
    var erledigtAm: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        beschreibung = Coerce.str(f["beschreibung"]) ?? ""
        kategorie = Coerce.str(f["kategorie"])
        groesse = Coerce.str(f["groesse"])
        prioritaet = Coerce.str(f["prioritaet"]) ?? "normal"
        notizen = Coerce.str(f["notizen"])
        erledigt = Coerce.bool(f["erledigt"])
        erledigtAm = Coerce.str(f["erledigt_am"])
    }
}

// MARK: - Stats & Matrix

struct SamuStats {
    var gesamt: Int = 0
    var geschaetzterWert: Double = 0
    var nachStatus: [(status: String, count: Int)] = []

    init() {}
    init(object o: [String: Any]) {
        gesamt = Coerce.int(o["gesamt"]) ?? 0
        geschaetzterWert = Coerce.double(o["geschaetzter_wert"]) ?? 0
        if let arr = o["nach_status"] as? [[String: Any]] {
            nachStatus = arr.map { (Coerce.str($0["status"]) ?? "", Coerce.int($0["count"]) ?? 0) }
        }
    }
}

struct SamuMatrixCell {
    let kategorie: String
    let groesse: String
    let count: Int
    init?(_ f: [String: Any]) {
        guard let k = Coerce.str(f["kategorie"]), let g = Coerce.str(f["groesse"]) else { return nil }
        kategorie = k; groesse = g; count = Coerce.int(f["count"]) ?? 0
    }
}

// MARK: - Visuelle Konfiguration (Status/Priorität/Zustand)

enum SamuStyle {
    struct StatusInfo { let emoji: String; let label: String; let color: Color }

    static let status: [String: StatusInfo] = [
        "aktiv":       StatusInfo(emoji: "🌟", label: "Aktiv",     color: Color(hex: "16A34A")),
        "eingelagert": StatusInfo(emoji: "📦", label: "Im Schrank", color: Color(hex: "2563EB")),
        "aussortiert": StatusInfo(emoji: "👋", label: "Tschüss",   color: Color(hex: "EA580C")),
        "verkauft":    StatusInfo(emoji: "🎉", label: "Verkauft",  color: Color(hex: "9333EA")),
    ]
    static func statusInfo(_ s: String) -> StatusInfo { status[s] ?? status["aktiv"]! }

    /// Alle wählbaren Status (feste Reihenfolge) — für das Bearbeiten-Formular.
    static let statusOrder = ["aktiv", "eingelagert", "aussortiert", "verkauft"]

    static let zustandLabels: [(value: String, label: String)] = [
        ("neu", "Neu ✨"), ("sehr_gut", "Sehr gut"), ("gut", "Gut"), ("gebraucht", "Gebraucht"),
    ]

    struct PrioInfo { let emoji: String; let label: String; let color: Color }
    static let prio: [String: PrioInfo] = [
        "hoch":    PrioInfo(emoji: "🔴", label: "Dringend", color: Color(hex: "DC2626")),
        "normal":  PrioInfo(emoji: "🔵", label: "Normal",   color: Color(hex: "2563EB")),
        "niedrig": PrioInfo(emoji: "⚪", label: "Niedrig",  color: Color(hex: "6B7280")),
    ]
    static func prioInfo(_ p: String) -> PrioInfo { prio[p] ?? prio["normal"]! }
    static let prioOrder = ["hoch", "normal", "niedrig"]
}

/// Inventar-Filterzustand.
struct SamuFilters: Equatable {
    var status: String? = nil      // exakter Serverfilter
    var typ: String? = nil         // kleidung | spielzeug
    var kategorie: String? = nil
    var groesse: String? = nil
    var marke: String? = nil       // NUR clientseitig
    var search: String = ""

    var isActive: Bool { status != nil || typ != nil || kategorie != nil || groesse != nil || marke != nil || !search.isEmpty }
}
