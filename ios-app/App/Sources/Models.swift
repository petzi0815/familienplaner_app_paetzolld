import Foundation

// JSONDecoder nutzt .convertFromSnakeCase → storage_key → storageKey usw.

struct Lebensbereich: Decodable, Identifiable {
    let key: String
    let titel: String
    let emoji: String?
    var id: String { key }
}
struct LebensbereichList: Decodable { let data: [Lebensbereich]; let total: Int }

struct FotoInboxItem: Decodable, Identifiable {
    let id: Int
    let storageKey: String
    let storageKeyUrl: String?
    let bereich: String?
    let status: String
    let notiz: String?
    let erstelltAm: String?
    let zugeordnetResource: String?
}
struct FotoInboxList: Decodable { let data: [FotoInboxItem]; let total: Int }

struct FotoUploadResult: Decodable {
    let id: Int
    let status: String
    let url: String?
}

// ── ID, die als Zahl ODER String kommen kann (elisbooks nutzt TEXT-PK) ──
struct FlexibleID: Decodable, Hashable {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = String(i) }
        else if let s = try? c.decode(String.self) { value = s }
        else { value = "" }
    }
}

// ── Dashboard (GET /api/v1/dashboard/today) ──
struct DashboardToday: Decodable {
    let date: String
    let termineUpcoming: [TerminShort]
    let remindersDue: Int
    let nextTrip: NextTrip?
    let gartenOffen: Int
    let vorratBaldAblaufend: [VorratShort]
    let counts: DashboardCounts
}
struct TerminShort: Decodable, Identifiable {
    let id: Int
    let title: String
    let date: String
    let time: String?
    let category: String?
}
struct NextTrip: Decodable {
    let id: Int
    let title: String
    let destination: String?
    let startDate: String
    let daysUntil: Int?
}
struct VorratShort: Decodable, Identifiable {
    let id: Int
    let name: String
    let mhd: String?
}
struct DashboardCounts: Decodable {
    let samuItems: Int
    let geschenkeOffen: Int
    let buecher: Int
    let vertraege: Int
    let fotoInboxNeu: Int
}

// ── Cross-Domain-Suche (GET /api/v1/search) ──
struct SearchResponse: Decodable { let query: String; let engine: String; let count: Int; let results: [SearchHit] }
struct SearchHit: Decodable, Identifiable {
    let resource: String
    let domain: String
    let label: String
    let entityId: FlexibleID
    let display: String
    var id: String { "\(resource)#\(entityId.value)" }

    enum CodingKeys: String, CodingKey {
        case resource, domain, label, display
        case entityId = "id"
    }
}

// ── Reisen (Karten-Ansicht) ──
struct Trip: Decodable, Identifiable {
    let id: Int
    let title: String
    let destination: String?
    let startDate: String?
    let endDate: String?
    let lat: Double?
    let lng: Double?
    let coverImage: String?
}
struct TripList: Decodable { let data: [Trip]; let total: Int }

struct TripActivity: Decodable, Identifiable {
    let id: Int
    let title: String
    let category: String?
    let location: String?
    let lat: Double?
    let lng: Double?
}
struct TripActivityList: Decodable { let data: [TripActivity]; let total: Int }

// ── Generischer Bereiche-Browser (aus /agent/capabilities) ──
struct ResourceImageSpec: Decodable { let col: String; let multi: Bool; let area: String }
struct ResourceInfo: Decodable, Identifiable {
    let key: String
    let domain: String
    let label: String
    let readonly: Bool
    let primaryKey: String
    let image: ResourceImageSpec?
    let columns: [String]
    var id: String { key }
}
struct Capabilities: Decodable { let resources: [ResourceInfo] }

/// Ein Datensatz mit dynamischen Feldern (Rohwerte aus JSONSerialization).
struct GenericRecord: Identifiable {
    let id: String
    let fields: [String: Any]
}

/// Lebensbereich (Domain) mit seinen Ressourcen — clientseitig aus den Capabilities gebaut.
struct BereichDomain: Identifiable {
    let key: String
    let title: String
    let emoji: String
    let resources: [ResourceInfo]
    var id: String { key }
}

// ── Anzeige-Helfer für dynamische Felder ──
func fieldString(_ value: Any?) -> String {
    switch value {
    case nil, is NSNull: return ""
    case let s as String: return s
    case let a as [Any]: return a.map { fieldString($0) }.joined(separator: ", ")
    default: return String(describing: value!)
    }
}

private let titleKeys = ["title", "titel", "name", "friendly_name", "bezeichnung", "anbieter", "item", "local_text", "problem", "frage"]
private let subtitleKeys = ["date", "datum", "kategorie", "category", "status", "mhd", "start_date", "destination", "menge", "marke", "author"]

func recordTitle(_ fields: [String: Any]) -> String {
    for k in titleKeys { let v = fieldString(fields[k]); if !v.isEmpty { return v } }
    return "#\(fieldString(fields["id"]))"
}
func recordSubtitle(_ fields: [String: Any], titleShown: String) -> String? {
    for k in subtitleKeys {
        let v = fieldString(fields[k]); if !v.isEmpty && v != titleShown {
            return (k == "date" || k == "datum" || k == "mhd" || k == "start_date") ? DateText.pretty(v) : v
        }
    }
    return nil
}
func recordImageURL(_ fields: [String: Any], _ spec: ResourceImageSpec?) -> String? {
    recordImageURLs(fields, spec).first
}
/// Alle Bild-URLs eines Datensatzes (mehrere bei `multi`).
func recordImageURLs(_ fields: [String: Any], _ spec: ResourceImageSpec?) -> [String] {
    guard let spec else { return [] }
    if spec.multi { return (fields[spec.col + "_urls"] as? [Any])?.compactMap { $0 as? String } ?? [] }
    if let u = fields[spec.col + "_url"] as? String { return [u] }
    return []
}
/// snake_case → hübsches Label.
func prettyColumn(_ name: String) -> String {
    name.replacingOccurrences(of: "_", with: " ")
        .split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
}

// ── UI/UX-Feldformatierung (statt stumpfer Tabellen mit JSON-Rohwerten) ──
enum FieldFormat: String {
    case date, datetime, time, bool, badge, jsonList, keyValue, url, number, price, multiline, plain, hidden
}

/// Pro-Ressource-Anzeige-Spec (aus dem UI-Spec-Workflow; sonst generisch geraten).
struct DisplaySpec {
    var layout: String = "generic"
    var titleField: String?
    var subtitleField: String?
    var badgeField: String?
    var heroImageField: String?
    var primaryFields: [String] = []
    var hidden: Set<String> = []
    var formats: [String: FieldFormat] = [:]
    var listSubtitle: String?
}

/// Technische/interne Felder immer ausblenden.
private let ALWAYS_HIDDEN: Set<String> = [
    "id", "created_at", "updated_at", "erstellt_am", "erfasst_am", "added_at", "aktualisiert_am",
    "verbraucht_am", "sort_order", "cron_job_id", "reminder_sent", "source", "storage_key",
    "lat", "lng", "google_maps_url",
]
func isTechnicalField(_ col: String) -> Bool {
    if ALWAYS_HIDDEN.contains(col) { return true }
    return col.hasSuffix("_id") || col.hasSuffix("_url") || col.hasSuffix("_urls")
}

func isDateString(_ s: String) -> Bool {
    s.count >= 10 && s.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}", options: .regularExpression) != nil
}

/// JSON-Array-String (`["a","b"]`) → Werte; sonst der Rohwert als Ein-Element-Liste.
func parseJSONList(_ s: String) -> [String] {
    if let data = s.data(using: .utf8), let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
        return arr.map { fieldString($0) }.filter { !$0.isEmpty }
    }
    return s.isEmpty ? [] : [s]
}

/// JSON-Objekt-String (`{"a":1,"b":"x"}`) → geordnete Key/Value-Paare; sonst leer (kein Objekt).
func parseJSONObject(_ s: String) -> [(key: String, value: String)] {
    guard let data = s.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
    return obj.keys.sorted().map { (key: $0, value: fieldString(obj[$0])) }.filter { !$0.value.isEmpty }
}

/// Format raten, wenn die Spec keins vorgibt.
func guessFormat(_ col: String, _ value: Any?) -> FieldFormat {
    if isTechnicalField(col) { return .hidden }
    let s = fieldString(value)
    if s.isEmpty { return .hidden }
    if s.hasPrefix("[") && s.hasSuffix("]") { return .jsonList }
    if s.hasPrefix("{") && s.hasSuffix("}") && !parseJSONObject(s).isEmpty { return .keyValue }
    if s.hasPrefix("http://") || s.hasPrefix("https://") { return .url }
    if isDateString(s) { return .date }
    if col.hasPrefix("is_") || col.hasPrefix("has_") || ["restock", "packed", "kid_friendly", "erledigt"].contains(col) { return .bool }
    if ["status", "kategorie", "category", "anlass", "typ", "priorität", "prioritaet", "link_type", "doc_type"].contains(col) { return .badge }
    if s.count > 90 { return .multiline }
    return .plain
}

private let dateTimeIn: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f }()
func prettyDateTime(_ s: String) -> String {
    if let d = dateTimeIn.date(from: s) {
        let out = DateFormatter(); out.locale = Locale(identifier: "de_DE"); out.dateStyle = .medium; out.timeStyle = .short
        return out.string(from: d)
    }
    return DateText.pretty(s)
}
