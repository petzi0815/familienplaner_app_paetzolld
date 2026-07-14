import SwiftUI

// Native Wunschliste-Modelle (Samus Geschenke-Wunschliste). Backend = Kompat-API
// `/api/wunschliste/events` + `/api/wunschliste/items` (bare Arrays, snake_case, Booleans als 0/1).
// Besonderheiten (siehe Audit): `image_url` ist eine ROHE externe URL (kein Storage-Key),
// `price` ist Freitext (nicht numerisch), `category` ist Freitext (UI speichert Emoji),
// `price_comparison` ist ein JSON-String, `priority` ist gemischt-typisiert (nicht angefasst).

// MARK: - Event (Anlass)

struct WunschEvent: Identifiable, Equatable {
    let id: Int
    var name: String
    var emoji: String
    var date: String?           // YYYY-MM-DD
    var type: String
    var notes: String?
    var archived: Bool
    var erinnerungenAktiv: Bool
    var itemCount: Int          // server-berechnet (alle Status)
    var openCount: Int          // server-berechnet (status = offen)

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        name = Coerce.str(f["name"]) ?? "Anlass"
        emoji = Coerce.str(f["emoji"]) ?? "🎁"
        date = Coerce.str(f["date"])
        type = Coerce.str(f["type"]) ?? "einmalig"
        notes = Coerce.str(f["notes"])
        archived = Coerce.bool(f["archived"])
        erinnerungenAktiv = Coerce.bool(f["erinnerungen_aktiv"])
        itemCount = Coerce.int(f["item_count"]) ?? 0
        openCount = Coerce.int(f["open_count"]) ?? 0
    }

    static func == (a: WunschEvent, b: WunschEvent) -> Bool {
        a.id == b.id && a.name == b.name && a.emoji == b.emoji && a.date == b.date
            && a.erinnerungenAktiv == b.erinnerungenAktiv && a.itemCount == b.itemCount
            && a.openCount == b.openCount && a.archived == b.archived
    }

    /// Countdown-Badge aus dem Datum (Text + Farbe), sonst nil.
    var countdown: WunschCountdown? {
        guard let d = date, let target = DateText.parse(date: d) else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: target)).day ?? 0
        return WunschCountdown(days: days)
    }
}

/// Countdown-Darstellung eines Event-Datums (Tage bis zum Anlass).
struct WunschCountdown {
    let days: Int
    var text: String {
        if days < 0 { return "vorbei" }
        if days == 0 { return "🎉 Heute!" }
        if days <= 7 { return "⏰ \(days) Tage" }
        return "\(days) Tage"
    }
    var color: Color {
        if days < 0 { return Color(hex: "6B7280") }
        if days == 0 { return Color(hex: "DC2626") }
        if days <= 7 { return Color(hex: "EA580C") }
        if days <= 30 { return Color(hex: "D97706") }
        return Color(hex: "6B7280")
    }
    var isToday: Bool { days == 0 }
}

// MARK: - Item (Geschenkidee)

struct WunschItem: Identifiable, Equatable {
    let id: Int
    var eventId: Int
    var title: String
    var description: String?
    var price: String?          // Freitext (z.B. "~27-35€")
    var url: String?
    var imageURL: String?       // ROHE externe URL
    var category: String?       // Freitext / Emoji
    var status: String          // offen | gekauft | geschenkt
    var purchasedBy: String?
    var notes: String?
    var ean: String?
    var priceComparison: [WunschPriceEntry]   // aus JSON-String geparst
    var eventName: String?
    var eventEmoji: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        eventId = Coerce.int(f["event_id"]) ?? 0
        title = Coerce.str(f["title"]) ?? "Ohne Titel"
        description = Coerce.str(f["description"])
        price = Coerce.str(f["price"])
        url = Coerce.str(f["url"])
        imageURL = Coerce.str(f["image_url"])
        category = Coerce.str(f["category"])
        status = Coerce.str(f["status"]) ?? "offen"
        purchasedBy = Coerce.str(f["purchased_by"])
        notes = Coerce.str(f["notes"])
        ean = Coerce.str(f["ean"])
        priceComparison = WunschPriceEntry.parse(f["price_comparison"])
        eventName = Coerce.str(f["event_name"])
        eventEmoji = Coerce.str(f["event_emoji"])
    }

    var isBook: Bool { category == "📚" }
    /// Kategorie-Pille zeigen (Buch-Kategorie steckt bereits im Bild-Tile).
    var showCategoryPill: Bool { (category?.isEmpty == false) && category != "📚" }
    /// Emoji-Fallback für das Bild-Tile.
    var fallbackEmoji: String { isBook ? "📚" : "🎁" }
    var hasURL: Bool { (url?.isEmpty == false) }
}

/// Ein Eintrag eines gespeicherten Preisvergleichs (`price_comparison`-JSON).
struct WunschPriceEntry: Identifiable, Equatable {
    let id = UUID()
    let shop: String
    let price: String
    let url: String?

    static func parse(_ raw: Any?) -> [WunschPriceEntry] {
        // Kann echtes Array ODER JSON-String sein.
        var arr: [Any] = []
        if let a = raw as? [Any] {
            arr = a
        } else if let s = raw as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty || t == "[]" || t == "null" { return [] }
            if let data = t.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                arr = parsed
            }
        }
        return arr.compactMap { el in
            guard let o = el as? [String: Any] else { return nil }
            let shop = Coerce.str(o["shop"]) ?? "Shop"
            let price = Coerce.str(o["price"]) ?? Coerce.double(o["price"]).map { String(format: "%g€", $0) } ?? "—"
            return WunschPriceEntry(shop: shop, price: price, url: Coerce.str(o["url"]))
        }
    }
}

// MARK: - Client-berechnete Kennzahlen (aus den geladenen Items, event-bezogen)

struct WunschStats {
    var total = 0
    var offen = 0
    var gekauft = 0
    var geschenkt = 0

    init() {}
    init(items: [WunschItem]) {
        total = items.count
        offen = items.filter { $0.status == "offen" }.count
        gekauft = items.filter { $0.status == "gekauft" }.count
        geschenkt = items.filter { $0.status == "geschenkt" }.count
    }
}

// MARK: - Visuelle Konfiguration

enum WunschStyle {
    struct StatusInfo { let emoji: String; let label: String; let color: Color }

    static let status: [String: StatusInfo] = [
        "offen":     StatusInfo(emoji: "⬜", label: "Offen",     color: Color(hex: "D97706")),
        "gekauft":   StatusInfo(emoji: "🛒", label: "Gekauft",   color: Color(hex: "2563EB")),
        "geschenkt": StatusInfo(emoji: "✅", label: "Geschenkt", color: Color(hex: "16A34A")),
    ]
    static func statusInfo(_ s: String) -> StatusInfo { status[s] ?? status["offen"]! }
    static let statusOrder = ["offen", "gekauft", "geschenkt"]

    /// Nächster Status im Zyklus offen → gekauft → geschenkt → offen.
    static func nextStatus(_ s: String) -> String {
        switch s {
        case "offen": return "gekauft"
        case "gekauft": return "geschenkt"
        default: return "offen"
        }
    }

    /// Kategorie-Auswahl (Wert = Emoji, wie das Original-Select).
    static let categories: [(value: String, label: String)] = [
        ("", "Kategorie…"),
        ("📚", "📚 Buch"), ("🧸", "🧸 Spielzeug"), ("👕", "👕 Kleidung"),
        ("👟", "👟 Schuhe"), ("🎨", "🎨 Kreativ"), ("🏊", "🏊 Outdoor"),
        ("🎵", "🎵 Musik"), ("🎁", "🎁 Sonstiges"),
    ]

    /// Emoji-Presets für neue Events (Emoji + optionaler Name-Vorschlag).
    static let eventPresets: [(emoji: String, name: String?)] = [
        ("🐣", "Ostern"), ("🎂", "Geburtstag"), ("🎄", "Weihnachten"), ("🎁", nil),
    ]

    static let accent = Color(hex: "AF52DE")   // Wunschliste-Lila
}

/// Wrapper für `.fullScreenCover(item:)` (eindeutig benannt, kein Klash mit Samus `ImageRef`).
struct WunschImageRef: Identifiable { let id = UUID(); let path: String }
