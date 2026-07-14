import SwiftUI

// Datenmodelle des Trauerkarten-Bereichs (migriert aus der Lovable/Supabase „memories-app").
// Backend = generische v1-Ressourcen trauerkarten / trauerkarten-personen / trauerkarten-kosten.

struct TrauerPerson: Identifiable, Hashable {
    let id: Int
    let name: String
    init(id: Int, name: String) { self.id = id; self.name = name }
    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        name = Coerce.str(f["name"]) ?? "—"
    }
}

struct Trauerkarte: Identifiable, Hashable {
    let id: Int
    var name: String
    var trauertext: String
    var geldbetrag: Double
    var personId: Int?
    var fotoPath: String?        // aufgelöster Media-Pfad (/api/v1/media/…)
    let createdAt: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        name = Coerce.str(f["name"]) ?? "—"
        trauertext = Coerce.str(f["trauertext"]) ?? ""
        geldbetrag = Coerce.double(f["geldbetrag"]) ?? 0
        personId = Coerce.int(f["person_id"])
        fotoPath = Coerce.str(f["foto_key_url"]) ?? Coerce.str(f["foto_key"]).flatMap { mediaURLPath(fromKey: $0) }
        createdAt = Coerce.str(f["created_at"])
    }
    static func == (a: Trauerkarte, b: Trauerkarte) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct KostenEintrag: Identifiable, Hashable {
    let id: Int
    var beschreibung: String
    var betrag: Double
    var istEinnahme: Bool
    var datum: String?
    var personId: Int?
    var belegPath: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        beschreibung = Coerce.str(f["beschreibung"]) ?? "—"
        betrag = Coerce.double(f["betrag"]) ?? 0
        istEinnahme = Coerce.bool(f["ist_einnahme"])
        datum = Coerce.str(f["datum"])
        personId = Coerce.int(f["person_id"])
        belegPath = Coerce.str(f["beleg_key_url"]) ?? Coerce.str(f["beleg_key"]).flatMap { mediaURLPath(fromKey: $0) }
    }
    static func == (a: KostenEintrag, b: KostenEintrag) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum TrauerTab: Hashable { case karten, kosten }

/// Pro-Person-Saldo (Kostenverteilung, informativ).
struct PersonSaldo: Identifiable {
    let id: Int
    let name: String
    let einnahmen: Double
    let ausgaben: Double
    var saldo: Double { einnahmen - ausgaben }
}

/// Eine optimierte Ausgleichszahlung (Schuldner → Gläubiger).
struct Ausgleichszahlung: Identifiable, Hashable {
    let id: Int
    let from: String
    let to: String
    let betrag: Double
}

// MARK: - Stil (respektvolle Schiefer-/Slate-Palette der Original-App)

enum TrauerStyle {
    static let primary = Color(hex: "475569")     // slate-600
    static let accent = Color(hex: "64748b")      // slate-500
    static let einnahme = Color(hex: "22c55e")    // grün
    static let ausgabe = Color(hex: "ef4444")     // rot
    static let saldoPos = Color(hex: "2563eb")    // blau
    static let saldoNeg = Color(hex: "f97316")    // orange

    static func saldoColor(_ v: Double) -> Color { v >= 0 ? saldoPos : saldoNeg }

    /// Betrag als „1.234,56 €" (de-DE).
    static func eur(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.locale = Locale(identifier: "de_DE")
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f €", v)
    }

    /// ISO-Datum (yyyy-MM-dd oder ISO-Timestamp) → „14.07.2026".
    static func prettyDate(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "" }
        let day = String(iso.prefix(10))
        let parts = day.split(separator: "-")
        guard parts.count == 3 else { return day }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }
}
