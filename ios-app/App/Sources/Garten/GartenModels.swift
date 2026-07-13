import SwiftUI

// Native Garten-Modelle. Backend = Kompat-API `/api/garten/*` (bare Arrays / Objekte, snake_case,
// Booleans als 0/1). Bilder: `bild_pfade` (JSON-Array von Storage-Keys). `metadata` = JSON-String.

// MARK: - Tabs

enum GartenTab: Hashable { case pflanzen, samen, pflege, pflanz, duenger }

// MARK: - Pflanze

struct GartenPflanze: Identifiable {
    let id: Int
    var name: String
    var art: String
    var sorte: String?
    var standort: String?
    var beschreibung: String?
    var bewaesserung: String   // hunter | manuell
    var status: String         // aktiv | entfernt
    var notizen: String?
    var erfasstAm: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        name = Coerce.str(f["name"]) ?? "Pflanze"
        art = Coerce.str(f["art"]) ?? ""
        sorte = Coerce.str(f["sorte"])
        standort = Coerce.str(f["standort"])
        beschreibung = Coerce.str(f["beschreibung"])
        bewaesserung = Coerce.str(f["bewaesserung"]) ?? "hunter"
        status = Coerce.str(f["status"]) ?? "aktiv"
        notizen = Coerce.str(f["notizen"])
        erfasstAm = Coerce.str(f["erfasst_am"])
    }

    var emoji: String { GartenStyle.artEmoji(art) }
    var artLabel: String { GartenStyle.cap(art) }
    var isHunter: Bool { bewaesserung == "hunter" }
    var bewaesserungBadge: String { isHunter ? "💧 Hunter" : "🪣 Manuell" }
    var bewaesserungColor: Color { isHunter ? Color(hex: "2563EB") : Color(hex: "D97706") }
}

// MARK: - Samen

struct GartenSamen: Identifiable {
    let id: Int
    var nummer: String
    var name: String
    var art: String?
    var sorte: String?
    var beschreibung: String?
    var pflanzVon: Int?
    var pflanzBis: Int?
    var vorziehenAb: Int?
    var ernteVon: Int?
    var ernteBis: Int?
    var aussaat2Von: Int?
    var aussaat2Bis: Int?
    var ernte2Von: Int?
    var ernte2Bis: Int?
    var standortEmpfehlung: String?
    var abstandCm: Int?
    var tiefeCm: Double?
    var keimzeitTage: Int?
    var hersteller: String?
    var bio: String?
    var samenfestRaw: Int?
    var botanisch: String?
    var keimtemp: String?
    var keimfaehigBis: String?
    var inhalt: String?
    var verwendung: String?
    var typ: String?
    var herkunft: String?
    var besonderheiten: String?
    var aktiv: Bool
    var bildPfade: [String]
    var erfasstAm: String?
    var metadata: [String: String]
    var notizen: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        nummer = Coerce.str(f["nummer"]) ?? ""
        name = Coerce.str(f["name"]) ?? "Samen"
        art = Coerce.str(f["art"])
        sorte = Coerce.str(f["sorte"])
        beschreibung = Coerce.str(f["beschreibung"])
        pflanzVon = Coerce.int(f["pflanz_von"])
        pflanzBis = Coerce.int(f["pflanz_bis"])
        vorziehenAb = Coerce.int(f["vorziehen_ab"])
        ernteVon = Coerce.int(f["ernte_von"])
        ernteBis = Coerce.int(f["ernte_bis"])
        aussaat2Von = Coerce.int(f["aussaat_2_von"])
        aussaat2Bis = Coerce.int(f["aussaat_2_bis"])
        ernte2Von = Coerce.int(f["ernte_2_von"])
        ernte2Bis = Coerce.int(f["ernte_2_bis"])
        standortEmpfehlung = Coerce.str(f["standort_empfehlung"])
        abstandCm = Coerce.int(f["abstand_cm"])
        tiefeCm = Coerce.double(f["tiefe_cm"])
        keimzeitTage = Coerce.int(f["keimzeit_tage"])
        hersteller = Coerce.str(f["hersteller"])
        bio = Coerce.str(f["bio"])
        samenfestRaw = Coerce.int(f["samenfest"])
        botanisch = Coerce.str(f["botanisch"])
        keimtemp = Coerce.str(f["keimtemp"])
        keimfaehigBis = Coerce.str(f["keimfaehig_bis"])
        inhalt = Coerce.str(f["inhalt"])
        verwendung = Coerce.str(f["verwendung"])
        typ = Coerce.str(f["typ"])
        herkunft = Coerce.str(f["herkunft"])
        besonderheiten = Coerce.str(f["besonderheiten"])
        aktiv = Coerce.bool(f["aktiv"])
        bildPfade = Coerce.stringArray(f["bild_pfade"])
        erfasstAm = Coerce.str(f["erfasst_am"])
        var meta: [String: String] = [:]
        for (k, v) in Coerce.jsonObject(f["metadata"]) { if let s = Coerce.str(v) { meta[k] = s } }
        metadata = meta
        notizen = Coerce.str(f["notizen"])
    }

    var isSamenfest: Bool { samenfestRaw == 1 }
    var emoji: String { GartenStyle.samenEmoji(art) }
    var imagePaths: [String] { bildPfade.compactMap { mediaURLPath(fromKey: $0) } }
    var firstImagePath: String? { imagePaths.first }

    /// Keimfähigkeit abgelaufen, wenn das gespeicherte Jahr < aktuelles Jahr.
    var isKeimfaehigExpired: Bool {
        guard let y = Int(keimfaehigBis ?? "") else { return false }
        return y < GartenStyle.currentYear
    }
}

// MARK: - Dünger

struct GartenDuenger: Identifiable {
    let id: Int
    var name: String
    var marke: String?
    var typ: String?
    var beschreibung: String?
    var geeignetFuer: String?
    var naehrstoffe: String?
    var dosierung: String?
    var intervallWochen: Int?
    var saisonVon: Int?
    var saisonBis: Int?
    var vorraetig: Bool
    var kauflink: String?
    var bildPfade: [String]
    var erfasstAm: String?
    var notizen: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        name = Coerce.str(f["name"]) ?? "Dünger"
        marke = Coerce.str(f["marke"])
        typ = Coerce.str(f["typ"])
        beschreibung = Coerce.str(f["beschreibung"])
        geeignetFuer = Coerce.str(f["geeignet_fuer"])
        naehrstoffe = Coerce.str(f["naehrstoffe"])
        dosierung = Coerce.str(f["dosierung"])
        intervallWochen = Coerce.int(f["intervall_wochen"])
        saisonVon = Coerce.int(f["saison_von"])
        saisonBis = Coerce.int(f["saison_bis"])
        vorraetig = Coerce.bool(f["vorraetig"])
        kauflink = Coerce.str(f["kauflink"])
        bildPfade = Coerce.stringArray(f["bild_pfade"])
        erfasstAm = Coerce.str(f["erfasst_am"])
        notizen = Coerce.str(f["notizen"])
    }

    var typEmoji: String { typ.flatMap { GartenStyle.duengerTypEmoji[$0] } ?? "💩" }
    var typColor: Color { typ.flatMap { GartenStyle.duengerTypColor[$0] } ?? Color(hex: "B45309") }
    var typLabel: String { typ.map { GartenStyle.cap($0) } ?? "" }
    var firstImagePath: String? { bildPfade.compactMap { mediaURLPath(fromKey: $0) }.first }
    var kauflinkURL: URL? {
        guard let k = kauflink, !k.isEmpty else { return nil }
        return URL(string: k.hasPrefix("http") ? k : "https://\(k)")
    }
}

// MARK: - Aufgabe

struct GartenAufgabe: Identifiable {
    let id: Int
    var pflanzeId: Int?
    var samenId: Int?
    var duengerId: Int?
    var titel: String
    var beschreibung: String?
    var kategorie: String
    var monat: Int
    var geplantMonat: Int?
    var jahr: Int
    var erledigt: Bool
    var erledigtAm: String?
    var prioritaet: String
    var pflanzeName: String?
    var pflanzeArt: String?
    var duengerName: String?
    var duengerVorraetig: Int?
    // Clientseitige Überfällig-Markierung (nicht vom Server)
    var overdue: Bool = false
    var originalMonat: Int? = nil

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        pflanzeId = Coerce.int(f["pflanze_id"])
        samenId = Coerce.int(f["samen_id"])
        duengerId = Coerce.int(f["duenger_id"])
        titel = Coerce.str(f["titel"]) ?? ""
        beschreibung = Coerce.str(f["beschreibung"])
        kategorie = Coerce.str(f["kategorie"]) ?? ""
        monat = Coerce.int(f["monat"]) ?? 1
        geplantMonat = Coerce.int(f["geplant_monat"])
        jahr = Coerce.int(f["jahr"]) ?? 2026
        erledigt = Coerce.bool(f["erledigt"])
        erledigtAm = Coerce.str(f["erledigt_am"])
        prioritaet = Coerce.str(f["prioritaet"]) ?? "normal"
        pflanzeName = Coerce.str(f["pflanze_name"])
        pflanzeArt = Coerce.str(f["pflanze_art"])
        duengerName = Coerce.str(f["duenger_name"])
        duengerVorraetig = Coerce.int(f["duenger_vorraetig"])
    }

    var computedMonat: Int { geplantMonat ?? monat }
    var isShifted: Bool { (geplantMonat ?? monat) != monat }
    var isDuengenMissing: Bool { duengerVorraetig == 0 }

    /// Quell-Badge aus Pflanzenart bzw. Samen-Herkunft.
    var quellBadge: GartenStyle.ArtLabelInfo? {
        if pflanzeId != nil {
            if let info = GartenStyle.artLabels[pflanzeArt ?? ""] { return info }
            return GartenStyle.ArtLabelInfo(emoji: "🌱", label: pflanzeName ?? "Pflanze", color: Color(hex: "16A34A"))
        }
        if samenId != nil {
            return GartenStyle.ArtLabelInfo(emoji: "🌱", label: "Samen", color: Color(hex: "0D9488"))
        }
        return nil
    }

    /// „🌾 Ernte ab …" aus der Beschreibung (nur bei Vorziehen/Pflanzen-Aufgaben).
    var ernteInfo: String? {
        guard kategorie == "vorziehen" || kategorie == "pflanzen", let b = beschreibung else { return nil }
        guard let r = b.range(of: "🌾 Ernte ab ") else { return nil }
        let rest = b[r.upperBound...]
        let end = rest.firstIndex(of: ".") ?? rest.endIndex
        let s = rest[..<end].trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }
}

// MARK: - Stats

struct GartenStats {
    struct ArtCount: Identifiable { let id = UUID(); let art: String; let count: Int }
    var pflanzenGesamt = 0
    var pflanzenAktiv = 0
    var pflanzenNachArt: [ArtCount] = []
    var samenGesamt = 0
    var samenAktiv = 0
    var aufgabenGesamt = 0
    var aufgabenOffen = 0
    var aufgabenErledigt = 0
    var duengerGesamt = 0
    var duengerVorraetig = 0
    var duengerFehlend = 0

    init(object o: [String: Any]) {
        if let p = o["pflanzen"] as? [String: Any] {
            pflanzenGesamt = Coerce.int(p["gesamt"]) ?? 0
            pflanzenAktiv = Coerce.int(p["aktiv"]) ?? 0
            if let arr = p["nach_art"] as? [[String: Any]] {
                pflanzenNachArt = arr.map { ArtCount(art: Coerce.str($0["art"]) ?? "", count: Coerce.int($0["count"]) ?? 0) }
            }
        }
        if let s = o["samen"] as? [String: Any] {
            samenGesamt = Coerce.int(s["gesamt"]) ?? 0
            samenAktiv = Coerce.int(s["aktiv"]) ?? 0
        }
        if let a = o["aufgaben"] as? [String: Any] {
            aufgabenGesamt = Coerce.int(a["gesamt"]) ?? 0
            aufgabenOffen = Coerce.int(a["offen"]) ?? 0
            aufgabenErledigt = Coerce.int(a["erledigt"]) ?? 0
        }
        if let d = o["duenger"] as? [String: Any] {
            duengerGesamt = Coerce.int(d["gesamt"]) ?? 0
            duengerVorraetig = Coerce.int(d["vorraetig"]) ?? 0
            duengerFehlend = Coerce.int(d["fehlend"]) ?? 0
        }
    }
}

// MARK: - GTS (Grünlandtemperatursumme)

struct GTSDay: Identifiable {
    let id = UUID()
    let date: String
    let cumulative: Double
    init(fields f: [String: Any]) {
        date = Coerce.str(f["date"]) ?? ""
        cumulative = Coerce.double(f["cumulative"]) ?? 0
    }
}

struct GTSPlantTip: Identifiable {
    let id = UUID()
    let gts: Int
    let label: String
    let emoji: String
    let reached: Bool
    let forecastDate: String?
    init(fields f: [String: Any]) {
        gts = Coerce.int(f["gts"]) ?? 0
        label = Coerce.str(f["label"]) ?? ""
        emoji = Coerce.str(f["emoji"]) ?? "🌱"
        reached = Coerce.bool(f["reached"])
        forecastDate = Coerce.str(f["forecast_date"])
    }
}

struct GTSFrostPlant: Identifiable {
    let id: Int
    let name: String
    let minTemp: Double
    let status: String  // draussen_ok | reinholen | drinnen_lassen
    let hinweis: String
    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        name = Coerce.str(f["name"]) ?? ""
        minTemp = Coerce.double(f["min_temp"]) ?? 0
        status = Coerce.str(f["status"]) ?? "drinnen_lassen"
        hinweis = Coerce.str(f["hinweis"]) ?? ""
    }
}

struct GTSResult {
    var date = ""
    var current: Double = 0
    var projected14d: Double = 0
    var threshold150Reached = false
    var threshold200Reached = false
    var forecastReach150: String?
    var forecastReach200: String?
    var remaining150: Double = 0
    var remaining200: Double = 0
    var history: [GTSDay] = []
    var forecast: [GTSDay] = []
    var plantTips: [GTSPlantTip] = []
    var frostPlants: [GTSFrostPlant] = []

    init(object o: [String: Any]) {
        date = Coerce.str(o["date"]) ?? ""
        current = Coerce.double(o["gts_current"]) ?? 0
        projected14d = Coerce.double(o["gts_projected_14d"]) ?? 0
        threshold150Reached = Coerce.bool(o["threshold_150_reached"])
        threshold200Reached = Coerce.bool(o["threshold_200_reached"])
        forecastReach150 = Coerce.str(o["forecast_reach_150"])
        forecastReach200 = Coerce.str(o["forecast_reach_200"])
        remaining150 = Coerce.double(o["remaining_150"]) ?? 0
        remaining200 = Coerce.double(o["remaining_200"]) ?? 0
        history = (o["history"] as? [[String: Any]] ?? []).map(GTSDay.init(fields:))
        forecast = (o["forecast"] as? [[String: Any]] ?? []).map(GTSDay.init(fields:))
        plantTips = (o["plant_tips"] as? [[String: Any]] ?? []).map(GTSPlantTip.init(fields:))
        frostPlants = (o["frost_plants"] as? [[String: Any]] ?? []).map(GTSFrostPlant.init(fields:))
    }

    var hasData: Bool { !date.isEmpty || !history.isEmpty }
}

// MARK: - Filter

struct GartenPflanzenFilter: Equatable {
    var art: String? = nil
    var bewaesserung: String? = nil
    var search: String = ""
}

struct GartenSamenFilter: Equatable {
    var aktiv: Int = 1          // -1 = alle, 0 = inaktiv, 1 = aktiv
    var samenfest: Int = -1     // -1 = alle, 0/1
    var keimfaehig: String = "" // "" | "ok" | "abgelaufen"
    var hersteller: String = ""
    var bio: String = ""
    var typ: String = ""
    var search: String = ""
}

struct GartenAufgabenFilter: Equatable {
    var erledigt: Int = -1      // -1 = alle, 0/1
    var bereich: String = "alle" // alle | rasen | baeume | anzucht
}

struct GartenDuengerFilter: Equatable {
    var typ: String = ""
    var vorraetig: Int = -1     // -1 = alle, 0/1
    var search: String = ""
}

// MARK: - Visuelle Konfiguration (1:1 zur Web-App)

enum GartenStyle {
    static var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    static func cap(_ s: String) -> String {
        s.isEmpty ? s : s.prefix(1).uppercased() + String(s.dropFirst())
    }

    // Pflanzen-Art-Emojis
    static let artEmojis: [String: String] = [
        "baum": "🌳", "strauch": "🌿", "staude": "🌺", "blume": "🌸",
        "gras": "🌾", "hecke": "🌳", "kletterpflanze": "🌿", "bodendecker": "🍀",
    ]
    static func artEmoji(_ art: String?) -> String { artEmojis[art ?? ""] ?? "🌿" }

    // Samen-Art-Emojis
    static let artSamenEmojis: [String: String] = [
        "Kräuter": "🌿", "Gemüse": "🥬", "Blume": "🌸", "Obst": "🍓", "Salat": "🥗",
    ]
    static func samenEmoji(_ art: String?) -> String { artSamenEmojis[art ?? ""] ?? "🌱" }

    // Aufgaben-Kategorien
    struct KategorieInfo { let emoji: String; let color: Color; let label: String }
    static let kategorien: [String: KategorieInfo] = [
        "duengen":      KategorieInfo(emoji: "🌱", color: Color(hex: "22C55E"), label: "Düngen"),
        "schneiden":    KategorieInfo(emoji: "✂️", color: Color(hex: "F97316"), label: "Schneiden"),
        "giessen":      KategorieInfo(emoji: "💧", color: Color(hex: "3B82F6"), label: "Wässern"),
        "pflanzen":     KategorieInfo(emoji: "🌱", color: Color(hex: "10B981"), label: "Pflanzen"),
        "ernten":       KategorieInfo(emoji: "🌽", color: Color(hex: "F59E0B"), label: "Ernten"),
        "maehen":       KategorieInfo(emoji: "🟡", color: Color(hex: "EAB308"), label: "Mähen"),
        "lueften":      KategorieInfo(emoji: "💨", color: Color(hex: "06B6D4"), label: "Lüften"),
        "aerifizieren": KategorieInfo(emoji: "🔵", color: Color(hex: "6366F1"), label: "Aerifizieren"),
        "sanden":       KategorieInfo(emoji: "🟤", color: Color(hex: "D97706"), label: "Sanden"),
        "nachsaeen":    KategorieInfo(emoji: "🌱", color: Color(hex: "84CC16"), label: "Nachsäen"),
        "bodenanalyse": KategorieInfo(emoji: "🔬", color: Color(hex: "A855F7"), label: "Bodenanalyse"),
        "ph_messen":    KategorieInfo(emoji: "⚗️", color: Color(hex: "8B5CF6"), label: "pH messen"),
        "vorziehen":    KategorieInfo(emoji: "🌱", color: Color(hex: "14B8A6"), label: "Vorziehen"),
    ]
    static func kategorie(_ k: String) -> KategorieInfo {
        kategorien[k] ?? KategorieInfo(emoji: "🌱", color: Color(hex: "22C55E"), label: k)
    }

    // Aufgaben-Quell-Badge (nach Pflanzenart)
    struct ArtLabelInfo { let emoji: String; let label: String; let color: Color }
    static let artLabels: [String: ArtLabelInfo] = [
        "rasen":          ArtLabelInfo(emoji: "🌿", label: "Rasen", color: Color(hex: "059669")),
        "gras":           ArtLabelInfo(emoji: "🌿", label: "Rasen", color: Color(hex: "059669")),
        "baum":           ArtLabelInfo(emoji: "🌳", label: "Baum", color: Color(hex: "15803D")),
        "strauch":        ArtLabelInfo(emoji: "🌿", label: "Strauch", color: Color(hex: "65A30D")),
        "staude":         ArtLabelInfo(emoji: "🌸", label: "Staude", color: Color(hex: "DB2777")),
        "hecke":          ArtLabelInfo(emoji: "🌲", label: "Hecke", color: Color(hex: "16A34A")),
        "kletterpflanze": ArtLabelInfo(emoji: "🌱", label: "Kletterpflanze", color: Color(hex: "0D9488")),
        "kuebelpflanze":  ArtLabelInfo(emoji: "🪴", label: "Kübelpflanze", color: Color(hex: "D97706")),
        "gemuese":        ArtLabelInfo(emoji: "🥬", label: "Gemüse", color: Color(hex: "22C55E")),
        "kraut":          ArtLabelInfo(emoji: "🌿", label: "Kräuter", color: Color(hex: "10B981")),
    ]

    // Dünger-Typen
    static let duengerTypEmoji: [String: String] = [
        "fluessig": "💧", "granulat": "⚫", "staebchen": "🥢", "pulver": "🌫️",
        "organisch": "🍂", "kompost": "🌿", "sonstig": "📦",
    ]
    static let duengerTypColor: [String: Color] = [
        "fluessig": Color(hex: "3B82F6"), "granulat": Color(hex: "4B5563"),
        "staebchen": Color(hex: "F97316"), "pulver": Color(hex: "94A3B8"),
        "organisch": Color(hex: "D97706"), "kompost": Color(hex: "65A30D"),
        "sonstig": Color(hex: "737373"),
    ]
    static let duengerTypen = ["fluessig", "granulat", "staebchen", "pulver", "organisch", "kompost", "sonstig"]

    // Monatsnamen
    static let monatKurz = ["", "Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]
    static let monatLang = ["", "Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]
    static let monatInitial = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]  // 0-basiert (m-1)

    static func kurz(_ m: Int?) -> String { guard let m, m >= 1, m <= 12 else { return "" }; return monatKurz[m] }
    static func lang(_ m: Int?) -> String { guard let m, m >= 1, m <= 12 else { return "" }; return monatLang[m] }

    /// Monatsbereich als Kurz-Namen (z.B. Aussaat März–Mai) → ["Mär","Apr","Mai"].
    static func monthRange(_ von: Int?, _ bis: Int?) -> [String] {
        guard let v = von, let b = bis, v >= 1, b <= 12, v <= b else { return [] }
        return (v...b).map { monatKurz[$0] }
    }

    /// „von–bis" als zusammenhängender Text (lang oder kurz); nil wenn Grenzen fehlen.
    static func rangeText(_ von: Int?, _ bis: Int?, long: Bool = true) -> String? {
        guard let v = von, let b = bis, v >= 1, v <= 12, b >= 1, b <= 12 else { return nil }
        let name = long ? monatLang : monatKurz
        return "\(name[v])–\(name[b])"
    }

    /// Double ohne unnötige Nachkommastelle (2.0 → "2", 1.5 → "1.5").
    static func trimDouble(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    }

    // Rotierende Samen-Farben (Pflanzplan)
    struct SamenColorSet {
        let vorziehen: Color
        let aussaat: Color
        let ernte: Color
        let text: Color
        let bg: Color
    }
    static let samenColors: [SamenColorSet] = [
        SamenColorSet(vorziehen: Color(hex: "A855F7"), aussaat: Color(hex: "10B981"), ernte: Color(hex: "F59E0B"), text: Color(hex: "7E22CE"), bg: Color(hex: "FAF5FF")),
        SamenColorSet(vorziehen: Color(hex: "8B5CF6"), aussaat: Color(hex: "22C55E"), ernte: Color(hex: "F97316"), text: Color(hex: "6D28D9"), bg: Color(hex: "F5F3FF")),
        SamenColorSet(vorziehen: Color(hex: "D946EF"), aussaat: Color(hex: "14B8A6"), ernte: Color(hex: "EAB308"), text: Color(hex: "A21CAF"), bg: Color(hex: "FDF4FF")),
        SamenColorSet(vorziehen: Color(hex: "6366F1"), aussaat: Color(hex: "84CC16"), ernte: Color(hex: "F87171"), text: Color(hex: "4338CA"), bg: Color(hex: "EEF2FF")),
    ]
    static func samenColor(_ idx: Int) -> SamenColorSet { samenColors[idx % samenColors.count] }

    // GTS-Schwellenfarben
    static let gts150 = Color(hex: "FBBF24")
    static let gts200 = Color(hex: "34D399")
    static let gtsLow = Color(hex: "FCA5A5")
    static let gtsHistory = Color(hex: "34C759")
    static func gtsColor(_ v: Double) -> Color { v >= 200 ? gts200 : (v >= 150 ? gts150 : gtsLow) }
}
