import Foundation

/// Backend-Anbindung der Wunschliste an die Kompat-Endpunkte `/api/wunschliste/*`.
/// Bare Arrays für Listen, Objekte für Einzel-GET/Mutationen. Verben laut Routen:
/// GET/POST auf Collections, PATCH/DELETE auf `/{id}`.
/// Die externen Aktionen (`/enrich`, `/scrape`, `/pricecheck`) liefern 501 → werden hier
/// NICHT aufgerufen, sondern in der UI als „nicht verfügbar" deaktiviert dargestellt.
@MainActor
final class WunschlisteAPI {
    private let c: CompatClient
    init(settings: Settings) { c = CompatClient(settings: settings) }

    // ── Events ──
    func fetchEvents(includeArchived: Bool = false) async throws -> [WunschEvent] {
        var q: [URLQueryItem] = []
        if includeArchived { q.append(.init(name: "archived", value: "true")) }
        return try await c.getArray("/wunschliste/events", query: q).map(WunschEvent.init(fields:))
    }

    @discardableResult
    func addEvent(name: String, emoji: String, date: String?) async throws -> Int {
        var body: [String: Any] = ["name": name, "emoji": emoji]
        body["date"] = (date?.isEmpty == false) ? date! : NSNull()
        let r = try await c.send("/wunschliste/events", method: "POST", body: body)
        return Coerce.int(r["id"]) ?? 0
    }

    func updateEvent(_ id: Int, _ fields: [String: Any]) async throws {
        _ = try await c.send("/wunschliste/events/\(id)", method: "PATCH", body: fields)
    }

    func deleteEvent(_ id: Int) async throws {
        _ = try await c.send("/wunschliste/events/\(id)", method: "DELETE")
    }

    // ── Items ──
    func fetchItems(eventId: Int?) async throws -> [WunschItem] {
        var q: [URLQueryItem] = []
        if let e = eventId { q.append(.init(name: "event_id", value: String(e))) }
        return try await c.getArray("/wunschliste/items", query: q).map(WunschItem.init(fields:))
    }

    func fetchItem(_ id: Int) async throws -> WunschItem {
        WunschItem(fields: try await c.getObject("/wunschliste/items/\(id)"))
    }

    @discardableResult
    func addItem(_ fields: [String: Any]) async throws -> Int {
        let r = try await c.send("/wunschliste/items", method: "POST", body: fields)
        return Coerce.int(r["id"]) ?? 0
    }

    func updateItem(_ id: Int, _ fields: [String: Any]) async throws {
        _ = try await c.send("/wunschliste/items/\(id)", method: "PATCH", body: fields)
    }

    func deleteItem(_ id: Int) async throws {
        _ = try await c.send("/wunschliste/items/\(id)", method: "DELETE")
    }
}
