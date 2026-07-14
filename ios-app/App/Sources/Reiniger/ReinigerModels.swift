import SwiftUI

// Native Reiniger-Modelle. Backend = Kompat-API `/api/reiniger` (bare Arrays, snake_case,
// Booleans als 0/1). Zwei Entitaeten: Produkte (Reinigungsmittel) und Anwendungen (Flecken-/
// Pflegehinweise, verknuepft ueber `reiniger_id`). Bild = einzelner Storage-Key `bild_pfad`.

// MARK: - Produkt (Reinigungsmittel)

struct ReinigerProdukt: Identifiable, Equatable {
    let id: Int
    var name: String
    var marke: String?
    var kategorie: String?
    var einsatzorte: String?
    var geeignetFuer: String?
    var nichtGeeignetFuer: String?
    var flecken: String?
    var pflegehinweise: String?
    var sicherheit: String?
    var dosierung: String?
    var menge: String?
    var bildPfad: String?
    var status: String              // aktiv | leer | nachkaufen | entsorgt
    var restock: Bool
    var quelleUrl: String?
    var notizen: String?
    var erfasstAm: String?
    var aktualisiertAm: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        name = Coerce.str(f["name"]) ?? "Unbenannt"
        marke = Coerce.str(f["marke"])
        kategorie = Coerce.str(f["kategorie"])
        einsatzorte = Coerce.str(f["einsatzorte"])
        geeignetFuer = Coerce.str(f["geeignet_fuer"])
        nichtGeeignetFuer = Coerce.str(f["nicht_geeignet_fuer"])
        flecken = Coerce.str(f["flecken"])
        pflegehinweise = Coerce.str(f["pflegehinweise"])
        sicherheit = Coerce.str(f["sicherheit"])
        dosierung = Coerce.str(f["dosierung"])
        menge = Coerce.str(f["menge"])
        bildPfad = Coerce.str(f["bild_pfad"])
        status = Coerce.str(f["status"]) ?? "aktiv"
        restock = Coerce.bool(f["restock"])
        quelleUrl = Coerce.str(f["quelle_url"])
        notizen = Coerce.str(f["notizen"])
        erfasstAm = Coerce.str(f["erfasst_am"])
        aktualisiertAm = Coerce.str(f["aktualisiert_am"])
    }

    var imagePath: String? { reinigerImagePath(bildPfad) }
    /// Erste http-URL aus `quelle_url` (kann mehrere whitespace/`;`-getrennte URLs enthalten).
    var externalURL: URL? { reinigerFirstURL(quelleUrl) }
    var statusLabel: String { ReinigerStyle.statusLabel(status) }
    /// Untertitel `[marke, menge, status]` mit Trenner.
    var subtitle: String {
        var parts: [String] = []
        if let m = marke, !m.isEmpty { parts.append(m) }
        if let mn = menge, !mn.isEmpty { parts.append(mn) }
        parts.append(statusLabel)
        return parts.joined(separator: " · ")
    }
}

// MARK: - Anwendung (Flecken-/Pflegefall)

struct ReinigerAnwendung: Identifiable, Equatable {
    let id: Int
    var reinigerID: Int?
    var problem: String?
    var material: String?
    var anleitung: String?
    var warnhinweise: String?
    var prioritaet: Int
    var oberflaeche: String?
    var fleckArt: String?
    var anwendungsfall: String?
    var begruendung: String?
    // Joined-Felder aus dem verknuepften Produkt
    var produktName: String?
    var produktMarke: String?
    var produktKategorie: String?
    var produktBildPfad: String?
    var produktQuelleUrl: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        reinigerID = Coerce.int(f["reiniger_id"])
        problem = Coerce.str(f["problem"])
        material = Coerce.str(f["material"])
        anleitung = Coerce.str(f["anleitung"])
        warnhinweise = Coerce.str(f["warnhinweise"])
        prioritaet = Coerce.int(f["prioritaet"]) ?? 5
        oberflaeche = Coerce.str(f["oberflaeche"])
        fleckArt = Coerce.str(f["fleck_art"])
        anwendungsfall = Coerce.str(f["anwendungsfall"])
        begruendung = Coerce.str(f["begruendung"])
        produktName = Coerce.str(f["produkt_name"])
        produktMarke = Coerce.str(f["produkt_marke"])
        produktKategorie = Coerce.str(f["produkt_kategorie"])
        produktBildPfad = Coerce.str(f["produkt_bild_pfad"])
        produktQuelleUrl = Coerce.str(f["produkt_quelle_url"])
    }

    /// Oberflaeche mit Legacy-Fallback auf `material`.
    var surface: String? { oberflaeche ?? material }
    /// Titel = `fleck_art || anwendungsfall || problem`.
    var title: String { fleckArt ?? anwendungsfall ?? problem ?? "Anwendung" }
    /// Produktname fuers Link-Label (Joined bevorzugt).
    var produktLabel: String {
        var parts: [String] = []
        if let m = produktMarke, !m.isEmpty { parts.append(m) }
        if let n = produktName, !n.isEmpty { parts.append(n) }
        return parts.isEmpty ? "Produkt" : parts.joined(separator: " ")
    }
    var produktImagePath: String? { reinigerImagePath(produktBildPfad) }
    var externalURL: URL? { reinigerFirstURL(produktQuelleUrl) }
}

// MARK: - Stats

struct ReinigerStats {
    var active = 0
    var restock = 0
    var useCases = 0
    var categories: [(kategorie: String, count: Int)] = []

    init() {}
    init(object o: [String: Any]) {
        active = Coerce.int(o["active"]) ?? 0
        restock = Coerce.int(o["restock"]) ?? 0
        useCases = Coerce.int(o["useCases"]) ?? 0
        if let arr = o["categories"] as? [[String: Any]] {
            categories = arr.map { (Coerce.str($0["kategorie"]) ?? "", Coerce.int($0["count"]) ?? 0) }
        }
    }
}

// MARK: - Visuelle Konfiguration (Kategorien / Status)

enum ReinigerStyle {
    struct CatInfo { let label: String; let emoji: String; let color: Color }

    /// 15 Kategorien (Key -> Label/Emoji/Badge-Farbe). Unbekannte Keys fallen auf `spezial` zurueck.
    static let categories: [String: CatInfo] = [
        "allzweck": CatInfo(label: "Allzweck", emoji: "🧽", color: Color(hex: "0EA5E9")),
        "bad": CatInfo(label: "Bad", emoji: "🚿", color: Color(hex: "06B6D4")),
        "kueche": CatInfo(label: "Küche", emoji: "🍳", color: Color(hex: "F59E0B")),
        "boden": CatInfo(label: "Boden", emoji: "🪣", color: Color(hex: "10B981")),
        "waesche": CatInfo(label: "Wäsche", emoji: "👕", color: Color(hex: "8B5CF6")),
        "flecken": CatInfo(label: "Flecken", emoji: "🎯", color: Color(hex: "F43F5E")),
        "pflege": CatInfo(label: "Pflege", emoji: "✨", color: Color(hex: "84CC16")),
        "spezial": CatInfo(label: "Spezial", emoji: "🧴", color: Color(hex: "64748B")),
        "holzpflege_fleckentferner": CatInfo(label: "Holz-Flecken", emoji: "🪵", color: Color(hex: "EA580C")),
        "holzpflege_tannin_fleckentferner": CatInfo(label: "Tannin/Holz", emoji: "🪵", color: Color(hex: "CA8A04")),
        "scheuermilch_saeure_reiniger": CatInfo(label: "Säure/Scheuer", emoji: "🧴", color: Color(hex: "F43F5E")),
        "kochfeldreiniger_glaskeramik_politur": CatInfo(label: "Kochfeld", emoji: "♨️", color: Color(hex: "71717A")),
        "outdoor": CatInfo(label: "Outdoor", emoji: "🏡", color: Color(hex: "16A34A")),
        "stein": CatInfo(label: "Stein", emoji: "🧱", color: Color(hex: "78716C")),
        "terrasse": CatInfo(label: "Terrasse", emoji: "🏡", color: Color(hex: "059669")),
    ]

    /// Feste Reihenfolge fuer den Kategorie-Picker im Formular.
    static let categoryOrder = [
        "allzweck", "bad", "kueche", "boden", "waesche", "flecken", "pflege", "spezial",
        "holzpflege_fleckentferner", "holzpflege_tannin_fleckentferner",
        "scheuermilch_saeure_reiniger", "kochfeldreiniger_glaskeramik_politur",
        "outdoor", "stein", "terrasse",
    ]

    static func cat(_ key: String?) -> CatInfo { categories[key ?? ""] ?? categories["spezial"]! }

    static let statusLabels: [String: String] = [
        "aktiv": "Da", "leer": "Leer", "nachkaufen": "Nachkaufen", "entsorgt": "Entsorgt",
    ]
    static func statusLabel(_ s: String) -> String { statusLabels[s] ?? s }
}

enum ReinigerTab: Hashable { case inventar, ratgeber, einkauf }

// MARK: - Media-/URL-Helfer (bereichsspezifisch, greifen auf die geteilten Support-Funktionen zu)

/// `bild_pfad`-Storage-Key -> auth-faehiger Media-Pfad. Repliziert den PWA-Strip von `images/`.
func reinigerImagePath(_ key: String?) -> String? {
    guard let k = key, !k.isEmpty else { return nil }
    if k.hasPrefix("http") { return k }
    return mediaURLPath(fromKey: k.replacingOccurrences(of: "images/", with: ""))
}

/// Erste http(s)-URL aus einem Feld, das mehrere whitespace/`;`-getrennte URLs enthalten kann.
func reinigerFirstURL(_ raw: String?) -> URL? {
    guard let raw, !raw.isEmpty else { return nil }
    let tokens = raw.components(separatedBy: CharacterSet(charactersIn: " ;\n\t\r"))
    guard let token = tokens.first(where: { $0.hasPrefix("http") }) else { return nil }
    return URL(string: token)
}
