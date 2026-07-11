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
    guard let spec else { return nil }
    if spec.multi { return (fields[spec.col + "_urls"] as? [Any])?.compactMap { $0 as? String }.first }
    return fields[spec.col + "_url"] as? String
}
/// snake_case → hübsches Label.
func prettyColumn(_ name: String) -> String {
    name.replacingOccurrences(of: "_", with: " ")
        .split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
}
