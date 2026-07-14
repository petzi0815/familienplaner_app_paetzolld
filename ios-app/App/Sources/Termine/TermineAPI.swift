import Foundation

/// Backend-Anbindung des Familienkalenders an den Kompat-Endpunkt `/api/termine`.
/// Ein GET multiplext via `?mode=` (month|search|categories|conflicts); Antworten sind bare Arrays.
@MainActor
final class TermineAPI {
    private let c: CompatClient
    init(settings: Settings) { c = CompatClient(settings: settings) }

    /// Listen-Fetch (optional nach Kategorie gefiltert), `ORDER BY date ASC, time ASC`.
    func fetchList(category: String?) async throws -> [Termin] {
        var q: [URLQueryItem] = []
        if let cat = category, !cat.isEmpty { q.append(.init(name: "category", value: cat)) }
        return try await c.getArray("/termine", query: q).map(Termin.init(fields:))
    }

    /// Termine eines Kalendermonats (`month` ist 1-basiert).
    func fetchMonth(year: Int, month: Int) async throws -> [Termin] {
        let q: [URLQueryItem] = [
            .init(name: "mode", value: "month"),
            .init(name: "year", value: String(year)),
            .init(name: "month", value: String(month)),
        ]
        return try await c.getArray("/termine", query: q).map(Termin.init(fields:))
    }

    /// Volltextsuche über Titel/Beschreibung/Ort/Person/Notizen/Kategorie.
    func search(_ query: String) async throws -> [Termin] {
        try await c.getArray("/termine", query: [
            .init(name: "mode", value: "search"),
            .init(name: "q", value: query),
        ]).map(Termin.init(fields:))
    }

    /// Kategorien-Liste ({id,label,emoji,color}). Leer → Aufrufer nutzt den Default.
    func fetchCategories() async throws -> [TerminCategory] {
        try await c.getArray("/termine", query: [.init(name: "mode", value: "categories")]).compactMap { TerminCategory($0) }
    }

    /// Konflikt-Vorprüfung: offene Termine an `date` (inkl. mehrtägiger Spannen), optional ohne `exclude`.
    func conflicts(date: String, exclude: Int?) async throws -> [Termin] {
        var q: [URLQueryItem] = [.init(name: "mode", value: "conflicts"), .init(name: "date", value: date)]
        if let e = exclude { q.append(.init(name: "exclude", value: String(e))) }
        return try await c.getArray("/termine", query: q).map(Termin.init(fields:))
    }

    @discardableResult
    func create(_ body: [String: Any]) async throws -> Int {
        let r = try await c.send("/termine", method: "POST", body: body)
        return Coerce.int(r["id"]) ?? 0
    }

    func update(_ id: Int, _ body: [String: Any]) async throws {
        _ = try await c.send("/termine/\(id)", method: "PATCH", body: body)
    }

    /// Persönlichen Zustand (read/notify) des aufrufenden Users setzen (owner aus dem Key).
    func setState(_ id: Int, read: Bool? = nil, notify: Bool? = nil) async throws {
        var body: [String: Any] = [:]
        if let read { body["read"] = read }
        if let notify { body["notify"] = notify }
        _ = try await c.send("/termine/\(id)/mystate", method: "POST", body: body)
    }

    func delete(_ id: Int) async throws {
        _ = try await c.send("/termine/\(id)", method: "DELETE")
    }
}
