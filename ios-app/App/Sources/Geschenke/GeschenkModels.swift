import SwiftUI

// Native Geschenkplaner-Modelle. Backend = Kompat-API `/api/geschenkplaner/*`
// (bare Arrays fuer Listen, Objekte fuer Dashboard/Einzel-GET, snake_case, Booleans als 0/1).
// Kinder → Ereignisse (Anlaesse) → Geschenke, plus Einkauf + Archiv (vergangene Geschenke).

// MARK: - Kind

struct GKind: Identifiable, Equatable {
    let id: Int
    var name: String
    var geburtsdatum: String?
    var profil: String?
    var negativliste: String?
    var profilBestaetigtAm: String?
    var naechsteEreignisse: [GEreignis]
    var anlaesse: [GAnlassConfig]

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        name = Coerce.str(f["name"]) ?? "Kind"
        geburtsdatum = Coerce.str(f["geburtsdatum"])
        profil = Coerce.str(f["profil"])
        negativliste = Coerce.str(f["negativliste"])
        profilBestaetigtAm = Coerce.str(f["profil_bestaetigt_am"])
        naechsteEreignisse = (f["naechste_ereignisse"] as? [[String: Any]])?.map(GEreignis.init(fields:)) ?? []
        anlaesse = (f["anlaesse"] as? [[String: Any]])?.map(GAnlassConfig.init(fields:)) ?? []
    }

    /// Alter clientseitig aus dem Geburtsdatum (heute).
    var alter: Int? { geburtsdatum.flatMap { GDate.alterHeute($0) } }
}

// MARK: - Anlass-Konfiguration

struct GAnlassConfig: Identifiable, Equatable {
    let id: Int
    var kindId: Int
    var anlass: String          // geburtstag | ostern | weihnachten
    var aktiv: Bool
    var budgetMin: Int?
    var budgetMax: Int?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        kindId = Coerce.int(f["kind_id"]) ?? 0
        anlass = Coerce.str(f["anlass"]) ?? ""
        aktiv = Coerce.bool(f["aktiv"])
        budgetMin = Coerce.int(f["budget_min"])
        budgetMax = Coerce.int(f["budget_max"])
    }
}

// MARK: - Ereignis

struct GEreignis: Identifiable, Equatable {
    let id: Int
    var kindId: Int
    var anlass: String
    var datum: String
    var jahr: Int
    var alterZumEreignis: Int?
    var kindName: String?
    var geburtsdatum: String?
    var profil: String?
    var budgetMin: Int?
    var budgetMax: Int?
    var geschenke: [GGeschenk]
    var geschenkeCount: Int?
    var geschenkeAusgaben: Double?
    var geschenkeStatus: [String: Int]
    var profilBestaetigungAngefragt: Bool
    var profilBestaetigt: Bool
    var erinnerungenAktiv: Int

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        kindId = Coerce.int(f["kind_id"]) ?? 0
        anlass = Coerce.str(f["anlass"]) ?? ""
        datum = Coerce.str(f["datum"]) ?? ""
        jahr = Coerce.int(f["jahr"]) ?? 0
        alterZumEreignis = Coerce.int(f["alter_zum_ereignis"])
        kindName = Coerce.str(f["kind_name"])
        geburtsdatum = Coerce.str(f["geburtsdatum"])
        profil = Coerce.str(f["profil"])
        budgetMin = Coerce.int(f["budget_min"])
        budgetMax = Coerce.int(f["budget_max"])
        geschenke = (f["geschenke"] as? [[String: Any]])?.map(GGeschenk.init(fields:)) ?? []
        geschenkeCount = Coerce.int(f["geschenke_count"])
        geschenkeAusgaben = Coerce.double(f["geschenke_ausgaben"])
        var statusMap: [String: Int] = [:]
        if let m = f["geschenke_status"] as? [String: Any] {
            for (k, v) in m { statusMap[k] = Coerce.int(v) ?? 0 }
        }
        geschenkeStatus = statusMap
        profilBestaetigungAngefragt = Coerce.bool(f["profil_bestaetigung_angefragt"])
        profilBestaetigt = Coerce.bool(f["profil_bestaetigt"])
        erinnerungenAktiv = Coerce.int(f["erinnerungen_aktiv"]) ?? 1
    }

    /// Anzahl Geschenke: bevorzugt Server-Count (Dashboard), sonst Liste.
    var giftCount: Int { geschenkeCount ?? geschenke.count }
}

// MARK: - Geschenk

struct GGeschenk: Identifiable, Equatable {
    let id: Int
    var ereignisId: Int?
    var kindId: Int
    var titel: String
    var beschreibung: String?
    var preis: Double?
    var url: String?
    var shop: String?
    var status: String
    var istManuell: Bool
    var quelle: String?
    var notizen: String?
    var bildUrl: String?
    var ranking: Int?
    var begruendung: String?
    // gejoined (auf der Geschenke-Liste)
    var kindName: String?
    var anlass: String?
    var jahr: Int?
    var datum: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        ereignisId = Coerce.int(f["ereignis_id"])
        kindId = Coerce.int(f["kind_id"]) ?? 0
        titel = Coerce.str(f["titel"]) ?? ""
        beschreibung = Coerce.str(f["beschreibung"])
        preis = Coerce.double(f["preis"])
        url = Coerce.str(f["url"])
        shop = Coerce.str(f["shop"])
        status = Coerce.str(f["status"]) ?? "vorschlag"
        istManuell = Coerce.bool(f["ist_manuell"])
        quelle = Coerce.str(f["quelle"])
        notizen = Coerce.str(f["notizen"])
        bildUrl = Coerce.str(f["bild_url"])
        ranking = Coerce.int(f["ranking"])
        begruendung = Coerce.str(f["begruendung"])
        kindName = Coerce.str(f["kind_name"])
        anlass = Coerce.str(f["anlass"])
        jahr = Coerce.int(f["jahr"])
        datum = Coerce.str(f["datum"])
    }

    /// Bild-Pfad fuer AuthImage: externe URL direkt, sonst Media-Storage-Key.
    var imagePath: String? {
        guard let b = bildUrl, !b.isEmpty else { return nil }
        return mediaURLPath(fromKey: b)
    }

    /// Externe Shop-URL (https voranstellen, falls schemalos).
    var linkURL: URL? {
        guard let u = url, !u.isEmpty else { return nil }
        return URL(string: u.hasPrefix("http") ? u : "https://\(u)")
    }
}

// MARK: - Vergangenes Geschenk (Archiv)

struct GVergangenes: Identifiable, Equatable {
    let id: Int
    var kindId: Int
    var titel: String
    var anlass: String?
    var jahr: Int?
    var notizen: String?
    var kindName: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        kindId = Coerce.int(f["kind_id"]) ?? 0
        titel = Coerce.str(f["titel"]) ?? ""
        anlass = Coerce.str(f["anlass"])
        jahr = Coerce.int(f["jahr"])
        notizen = Coerce.str(f["notizen"])
        kindName = Coerce.str(f["kind_name"])
    }
}

// MARK: - Dashboard

struct GDashboard {
    var anstehende: [GEreignis] = []
    var offeneBestaetigung: [GEreignis] = []
    var statsKinder: Int = 0
    var statsEreignisse: Int = 0

    init(object o: [String: Any]) {
        anstehende = (o["anstehende"] as? [[String: Any]])?.map(GEreignis.init(fields:)) ?? []
        offeneBestaetigung = (o["offene_bestaetigung"] as? [[String: Any]])?.map(GEreignis.init(fields:)) ?? []
        if let s = o["stats"] as? [String: Any] {
            statsKinder = Coerce.int(s["kinder"]) ?? 0
            statsEreignisse = Coerce.int(s["anstehende_ereignisse"]) ?? 0
        }
    }

    /// Summe der geplanten Ausgaben ueber alle anstehenden Ereignisse (ohne Vorschlaege).
    var geplantSumme: Double { anstehende.reduce(0) { $0 + ($1.geschenkeAusgaben ?? 0) } }
}

// MARK: - Visuelle Konfiguration (Anlass, Status, Farben)

enum GStyle {
    // Anlaesse
    static let anlassEmojis: [String: String] = ["geburtstag": "🎂", "ostern": "🐣", "weihnachten": "🎄"]
    static let anlassLabels: [String: String] = ["geburtstag": "Geburtstag", "ostern": "Ostern", "weihnachten": "Weihnachten"]
    static let anlassOrder = ["geburtstag", "ostern", "weihnachten"]
    static func anlassEmoji(_ a: String) -> String { anlassEmojis[a] ?? "🎁" }
    static func anlassLabel(_ a: String) -> String { anlassLabels[a] ?? a }
    static func anlassColor(_ a: String) -> Color {
        switch a {
        case "geburtstag":  return Color(hex: "FBBF24") // amber-400
        case "ostern":      return Color(hex: "34D399") // emerald-400
        case "weihnachten": return Color(hex: "F87171") // red-400
        default:            return Color(hex: "D1D5DB") // gray-300
        }
    }

    // Status
    static let statuses = ["vorschlag", "ausgewaehlt", "bestellt", "verpackt", "vergeben"]
    static let statusLabels: [String: String] = [
        "vorschlag": "Vorschlag", "ausgewaehlt": "Ausgewählt", "bestellt": "Bestellt",
        "verpackt": "Verpackt", "vergeben": "Vergeben",
    ]
    static func statusLabel(_ s: String) -> String { statusLabels[s] ?? s }
    static func statusColor(_ s: String) -> Color {
        switch s {
        case "vorschlag":   return Color(hex: "6B7280") // gray-600
        case "ausgewaehlt": return Color(hex: "2563EB") // blue-700-ish
        case "bestellt":    return Color(hex: "D97706") // amber-700-ish
        case "verpackt":    return Color(hex: "16A34A") // green-700-ish
        case "vergeben":    return Color(hex: "9333EA") // purple-700-ish
        default:            return Color(hex: "6B7280")
        }
    }

    // Meta-Chip-Farben
    static let cPrice   = Color(hex: "16A34A")
    static let cShop    = Color(hex: "2563EB")
    static let cQuelle  = Color(hex: "9333EA")
    static let cUrl     = Color(hex: "4F46E5")
    static let cIdealo  = Color(hex: "0D9488")
    static let cGoogle  = Color(hex: "E11D48")
    static let cBegr    = Color(hex: "B45309")
    static let accent   = Color(hex: "F59E0B") // amber-500

    // Budget-Balken-Farbe nach Prozent (0…1)
    static func budgetColor(_ pct: Double) -> Color {
        if pct > 0.9 { return Color(hex: "F87171") }
        if pct > 0.6 { return Color(hex: "FBBF24") }
        return Color(hex: "34D399")
    }

    /// Waehrung wie die Web-App: "X.XX €" (Punkt-Dezimal, Leerzeichen vor €), en-dash fuer nil.
    static func eur(_ v: Double?) -> String {
        guard let v else { return "–" }
        return String(format: "%.2f €", v)
    }
}

// MARK: - Datums-/Countdown-Helfer (clientseitig, wie die Web-App)

struct GCountdown {
    let text: String
    let soon: Bool
    let past: Bool
}

enum GDate {
    /// Jahr/Monat/Tag aus einem ISO-String "YYYY-MM-DD" (nur die ersten 10 Zeichen).
    private static func ymd(_ s: String) -> (y: Int, m: Int, d: Int)? {
        let parts = String(s.prefix(10)).split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        return (y, m, d)
    }

    /// "YYYY-MM-DD" → "DD.MM.YYYY" (de-DE).
    static func fmt(_ s: String) -> String {
        guard let p = ymd(s) else { return s }
        return String(format: "%02d.%02d.%04d", p.d, p.m, p.y)
    }

    /// Lokales Datum (Mitternacht) aus ISO-String.
    private static func localDate(_ s: String) -> Date? {
        guard let p = ymd(s) else { return nil }
        var c = DateComponents()
        c.year = p.y; c.month = p.m; c.day = p.d
        return Calendar.current.date(from: c)
    }

    /// Countdown-Text + soon/past-Flags (identisch zur Web-Logik).
    static func countdown(_ s: String) -> GCountdown {
        guard let target = localDate(s) else { return GCountdown(text: fmt(s), soon: false, past: false) }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let diff = cal.dateComponents([.day], from: start, to: cal.startOfDay(for: target)).day ?? 0
        if diff < 0 { return GCountdown(text: "vor \(-diff) Tagen", soon: false, past: true) }
        if diff == 0 { return GCountdown(text: "Heute! 🎉", soon: true, past: false) }
        if diff == 1 { return GCountdown(text: "Morgen!", soon: true, past: false) }
        return GCountdown(text: "in \(diff) Tagen", soon: diff <= 14, past: false)
    }

    /// Alter (ganze Jahre) am Ereignisdatum.
    static func alter(geburt: String, am: String) -> Int? {
        guard let g = ymd(geburt), let d = ymd(am) else { return nil }
        var a = d.y - g.y
        if d.m < g.m || (d.m == g.m && d.d < g.d) { a -= 1 }
        return a
    }

    static func todayISO() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func alterHeute(_ geburt: String) -> Int? { alter(geburt: geburt, am: todayISO()) }

    static func currentYear() -> Int { Calendar.current.component(.year, from: Date()) }
}
