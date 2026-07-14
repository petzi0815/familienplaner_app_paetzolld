import SwiftUI

// Native Vorratskammer-Modelle. Backend = Kompat-API `/api/vorratskammer` (+ `/rezepte`).
// Listen kommen als BARE ARRAYS (`[{…}]`), Stats als bares Objekt, snake_case, Booleans als 0/1,
// Datum (MHD) als "yyyy-MM-dd". Decodierung tolerant via `Coerce`.

// MARK: - Lebensmittel

struct VorratItem: Identifiable, Equatable {
    let id: Int
    var name: String
    var marke: String?
    var kategorie: String          // trocken | kuehlschrank | gefrierfach (CHECK)
    var menge: String?             // Freitext: "500g", "2 Stk"
    var mhd: String?               // "yyyy-MM-dd"
    var bildPfad: String?          // Storage-Key (nur Agent/Fotobox schreibt Bilder)
    var status: String             // aktiv | verbraucht
    var restock: Bool              // "Nachkaufen wenn leer"
    var erfasstAm: String?
    var verbrauchtAm: String?
    var notizen: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        name = Coerce.str(f["name"]) ?? ""
        marke = Coerce.str(f["marke"])
        kategorie = Coerce.str(f["kategorie"]) ?? "trocken"
        menge = Coerce.str(f["menge"])
        mhd = Coerce.str(f["mhd"])
        bildPfad = Coerce.str(f["bild_pfad"])
        status = Coerce.str(f["status"]) ?? "aktiv"
        restock = Coerce.bool(f["restock"])
        erfasstAm = Coerce.str(f["erfasst_am"])
        verbrauchtAm = Coerce.str(f["verbraucht_am"])
        notizen = Coerce.str(f["notizen"])
    }

    /// Auth-fähiger Media-Pfad (entfernt defensiv ein führendes `images/`).
    var imagePath: String? {
        guard let b = bildPfad, !b.isEmpty else { return nil }
        return mediaURLPath(fromKey: b)
    }
}

// MARK: - Rezeptvorschlag (nur lesend, vom Agenten befüllt)

struct VorratRezept: Identifiable, Equatable {
    let id: Int
    var titel: String
    var url: String?               // externe Rezept-URL
    var quelle: String?
    var beschreibung: String?
    var zutatenMatch: String?      // Komma-getrennt (kein JSON)
    var bildUrl: String?           // externe Bild-URL (kein Media-Key)
    var erstelltAm: String?
    var notizen: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        titel = Coerce.str(f["titel"]) ?? "Rezept"
        url = Coerce.str(f["url"])
        quelle = Coerce.str(f["quelle"])
        beschreibung = Coerce.str(f["beschreibung"])
        zutatenMatch = Coerce.str(f["zutaten_match"])
        bildUrl = Coerce.str(f["bild_url"])
        erstelltAm = Coerce.str(f["erstellt_am"])
        notizen = Coerce.str(f["notizen"])
    }

    /// Externe URL mit https-Prefix, falls schemalos.
    var linkURL: URL? {
        guard let u = url, !u.isEmpty else { return nil }
        return URL(string: u.hasPrefix("http") ? u : "https://\(u)")
    }

    /// Zutaten-Chips aus dem Komma-String (getrimmt, leere raus).
    var zutaten: [String] {
        (zutatenMatch ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

// MARK: - Stats

struct VorratStats: Equatable {
    var total = 0
    var trocken = 0
    var kuehlschrank = 0
    var gefrierfach = 0
    var ablaufend = 0
    var einkaufsliste = 0

    init() {}
    init(object o: [String: Any]) {
        total = Coerce.int(o["total"]) ?? 0
        trocken = Coerce.int(o["trocken"]) ?? 0
        kuehlschrank = Coerce.int(o["kuehlschrank"]) ?? 0
        gefrierfach = Coerce.int(o["gefrierfach"]) ?? 0
        ablaufend = Coerce.int(o["ablaufend"]) ?? 0
        einkaufsliste = Coerce.int(o["einkaufsliste"]) ?? 0
    }
}

// MARK: - Kategorie-Konfiguration (CHECK trocken/kuehlschrank/gefrierfach)

enum VorratKat {
    struct Info { let label: String; let emoji: String }

    /// Feste Anzeige-Reihenfolge (auch für den Kategorie-Picker im Formular).
    static let order = ["trocken", "kuehlschrank", "gefrierfach"]

    static let map: [String: Info] = [
        "trocken":      Info(label: "Trocken",     emoji: "🗄️"),
        "kuehlschrank": Info(label: "Kühlschrank", emoji: "❄️"),
        "gefrierfach":  Info(label: "Gefrierfach", emoji: "🧊"),
    ]

    static func info(_ k: String) -> Info { map[k] ?? Info(label: k, emoji: "🍽️") }
}

// MARK: - MHD-Dringlichkeit (voll clientseitig aus dem "yyyy-MM-dd"-String)

enum VorratMhd {
    struct Info { let label: String; let color: Color; let expired: Bool }

    private static let parseFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; return f
    }()
    private static let displayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "dd.MM.yyyy"; f.locale = Locale(identifier: "de_DE"); f.timeZone = .current; return f
    }()

    static func date(_ iso: String?) -> Date? {
        guard let iso, iso.count >= 10 else { return nil }
        return parseFmt.date(from: String(iso.prefix(10)))
    }

    /// DD.MM.YYYY (de-DE) — wie `formatDate` der Original-Seite.
    static func formatDate(_ iso: String?) -> String? {
        guard let d = date(iso) else { return nil }
        return displayFmt.string(from: d)
    }

    /// Ganztägige Differenz (heute 00:00 → MHD 00:00) == ceil((mhd@00:00 − now)/Tag).
    static func diffDays(_ iso: String?) -> Int? {
        guard let d = date(iso) else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: d)
        return cal.dateComponents([.day], from: today, to: target).day
    }

    /// Farb-/Label-Bänder exakt wie die Original-Seite:
    /// <0 dunkelrot · <7 rot · ≤30 gelb (heller Grund → dunkler Text) · >30 grün.
    static func info(_ iso: String?) -> Info? {
        guard let diff = diffDays(iso) else { return nil }
        let color: Color
        if diff < 0 { color = Color(hex: "7F1D1D") }
        else if diff < 7 { color = Color(hex: "EF4444") }
        else if diff <= 30 { color = Color(hex: "FBBF24") }
        else { color = Color(hex: "22C55E") }
        let label: String
        if diff < 0 { label = "\(abs(diff))d abgelaufen!" }
        else if diff == 0 { label = "Heute!" }
        else if diff == 1 { label = "Morgen" }
        else { label = "\(diff) Tage" }
        return Info(label: label, color: color, expired: diff < 0)
    }
}

// MARK: - Filter & Tabs

struct VorratFilters: Equatable {
    var search: String = ""
}

enum VorratTab: Hashable { case vorrat, einkauf, ablaufend, rezepte }
