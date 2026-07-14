import SwiftUI

// Native Verträge-Modelle. Backend = generische v1-Ressource `/api/v1/vertraege`
// (Envelope `{data:[…]}`, snake_case, `kosten` REAL/nullable). KEINE Bilder, KEINE Kompat-Routen.
// Kategorie-Icon/-Farbe stecken nur in der JSON-Spalte `metadata._category` → Fallback = fester Katalog.

// MARK: - Vertrag (eine Zeile)

struct Vertrag: Identifiable, Equatable {
    let id: Int
    var kategorie: String?
    var anbieter: String?
    var bezeichnung: String?
    var kundennummer: String?
    var vertragsnummer: String?
    var kosten: Double?
    var kostenIntervall: String?
    var beginn: String?
    var laufzeitBis: String?
    var kuendigungsfrist: String?
    var verlaengerung: String?
    var status: String?
    var notizen: String?
    var erstelltAm: String?
    var aktualisiertAm: String?
    // aus metadata._category (einzige Quelle für Icon/Farbe in der DB)
    var metaIcon: String?
    var metaColorHex: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        kategorie = Coerce.str(f["kategorie"])
        anbieter = Coerce.str(f["anbieter"])
        bezeichnung = Coerce.str(f["bezeichnung"])
        kundennummer = Coerce.str(f["kundennummer"])
        vertragsnummer = Coerce.str(f["vertragsnummer"])
        kosten = Coerce.double(f["kosten"])
        kostenIntervall = Coerce.str(f["kosten_intervall"])
        beginn = Coerce.str(f["beginn"])
        laufzeitBis = Coerce.str(f["laufzeit_bis"])
        kuendigungsfrist = Coerce.str(f["kuendigungsfrist"])
        verlaengerung = Coerce.str(f["verlaengerung"])
        status = Coerce.str(f["status"])
        notizen = Coerce.str(f["notizen"])
        erstelltAm = Coerce.str(f["erstellt_am"])
        aktualisiertAm = Coerce.str(f["aktualisiert_am"])
        let meta = Coerce.jsonObject(f["metadata"])
        if let cat = meta["_category"] as? [String: Any] {
            metaIcon = Coerce.str(cat["icon"])
            metaColorHex = Coerce.str(cat["color"])
        }
    }

    /// Auf einen Monat normalisierte Kosten (0, wenn kein Betrag hinterlegt ist).
    var monatlich: Double { VertragStyle.toMonthly(kosten ?? 0, interval: kostenIntervall) }

    var kategorieName: String { kategorie ?? "Sonstige" }
    var catIcon: String { VertragStyle.icon(for: kategorieName, meta: metaIcon) }
    var catColor: Color { VertragStyle.color(for: kategorieName, metaHex: metaColorHex) }
}

// MARK: - Kategorie-Gruppe (für Übersicht/Akkordeon)

struct VertragGruppe: Identifiable {
    let name: String
    let icon: String
    let color: Color
    let contracts: [Vertrag]
    let monatlich: Double
    var id: String { name }
}

// MARK: - Stil (Intervall-Normalisierung, Kategorie-Katalog)

enum VertragStyle {
    /// Jahres-/Halbjahres-/Quartalsbeträge auf einen Monat herunterrechnen (sonst 1:1).
    static func toMonthly(_ amount: Double, interval: String?) -> Double {
        switch (interval ?? "").lowercased() {
        case "jährlich", "jaehrlich", "jahr", "yearly", "annually": return amount / 12
        case "halbjährlich", "halbjaehrlich": return amount / 6
        case "vierteljährlich", "vierteljaehrlich", "quartalsweise", "quartal": return amount / 3
        default: return amount   // monatlich / unbekannt
        }
    }

    /// Fester Kategorie-Katalog (Apple-Systemfarben) — 1:1 zur Web-App. Reihenfolge = Akkordeon-Reihenfolge.
    static let catalog: [(name: String, icon: String, hex: String)] = [
        ("Baufinanzierung",       "🏦", "FF3B30"),
        ("Krankenversicherung",   "🏥", "FF2D55"),
        ("Versicherungen",        "🛡️", "5856D6"),
        ("Vorsorge & Sparen",     "💰", "FF9500"),
        ("Wohnen & Nebenkosten",  "🏠", "34C759"),
        ("Mobilität",             "🚗", "007AFF"),
        ("Kinderbetreuung",       "👶", "FF9F0A"),
        ("Freizeit & Vereine",    "⛵", "00C7BE"),
        ("Banken",                "🏧", "8E8E93"),
    ]
    static let catOrder: [String] = catalog.map { $0.name }

    /// Position im Katalog (unbekannte Kategorien landen hinten).
    static func mapIndex(_ name: String) -> Int {
        catOrder.firstIndex(of: name) ?? Int.max
    }

    /// Icon: bevorzugt aus `metadata`, sonst Katalog, sonst neutrales 📄.
    static func icon(for name: String, meta: String?) -> String {
        if let m = meta, !m.isEmpty { return m }
        return catalog.first { $0.name == name }?.icon ?? "📄"
    }

    /// Farbe: bevorzugt aus `metadata` (Hex), sonst Katalog, sonst Systemgrau.
    static func color(for name: String, metaHex: String?) -> Color {
        if let h = metaHex, !h.isEmpty { return Color(hex: h) }
        if let hex = catalog.first(where: { $0.name == name })?.hex { return Color(hex: hex) }
        return Color(hex: "8E8E93")
    }

    /// Bekannte Intervalle für den Picker (Freitext bleibt möglich, dies sind nur Vorschläge).
    static let intervalle = ["monatlich", "vierteljährlich", "halbjährlich", "jährlich"]
    /// Übliche Status-Werte (Freitext, `aktiv` ist der Default).
    static let statusWerte = ["aktiv", "gekündigt", "pausiert", "beendet"]
}

// MARK: - Geldformatierung (de-DE, 2 Nachkommastellen, €-Suffix)

enum VertragFmt {
    private static let dec: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "de_DE")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()
    static func eur(_ v: Double) -> String { (dec.string(from: NSNumber(value: v)) ?? "0,00") + " €" }
    static func eurMo(_ v: Double) -> String { eur(v) + "/Mo" }
    /// Editierbarer Rohbetrag fürs Formular (Punkt als Dezimaltrenner).
    static func plain(_ v: Double) -> String { String(format: "%.2f", v) }
}

// MARK: - Filter / Sortierung / Tabs

enum VertraegeTab: Hashable { case uebersicht, liste }

enum VertragSort: String, CaseIterable {
    case kategorie, anbieter, kostenDesc
    var label: String {
        switch self {
        case .kategorie: return "Kategorie"
        case .anbieter: return "Anbieter"
        case .kostenDesc: return "Kosten ↓"
        }
    }
}

struct VertraegeFilters: Equatable {
    var search: String = ""
    var kategorie: String? = nil
    var sort: VertragSort = .kategorie
    var isActive: Bool { !search.isEmpty || kategorie != nil }
}

/// Ziel des Bearbeiten-/Neu-Sheets (`vertrag == nil` → neuer Vertrag).
struct VertragEditRef: Identifiable {
    let id = UUID()
    let vertrag: Vertrag?
}
