import Foundation

/// Backend-Anbindung des Reiniger-Bereichs an die Kompat-Endpunkte unter `/api/reiniger`.
/// Bare-Array-Antworten (Produkte, Anwendungen), Objekt-Antworten (Stats, Einzel-GET).
@MainActor
final class ReinigerAPI {
    private let c: CompatClient
    init(settings: Settings) { c = CompatClient(settings: settings) }

    // MARK: - Produkte

    func fetchItems(status: String? = nil, kategorie: String? = nil, search: String = "") async throws -> [ReinigerProdukt] {
        var q: [URLQueryItem] = []
        if let s = status { q.append(.init(name: "status", value: s)) }
        if let k = kategorie { q.append(.init(name: "kategorie", value: k)) }
        if !search.isEmpty { q.append(.init(name: "search", value: search)) }
        return try await c.getArray("/reiniger", query: q).map(ReinigerProdukt.init(fields:))
    }

    func fetchItem(_ id: Int) async throws -> ReinigerProdukt {
        ReinigerProdukt(fields: try await c.getObject("/reiniger/\(id)"))
    }

    func fetchStats() async throws -> ReinigerStats {
        ReinigerStats(object: try await c.getObject("/reiniger", query: [.init(name: "stats", value: "true")]))
    }

    // MARK: - Anwendungen

    func fetchAnwendungen(search: String = "", reinigerID: Int? = nil) async throws -> [ReinigerAnwendung] {
        var q: [URLQueryItem] = [.init(name: "anwendungen", value: "true")]
        if !search.isEmpty { q.append(.init(name: "search", value: search)) }
        if let r = reinigerID { q.append(.init(name: "reiniger_id", value: String(r))) }
        return try await c.getArray("/reiniger", query: q).map(ReinigerAnwendung.init(fields:))
    }

    // MARK: - Schreiben

    @discardableResult
    func createProduct(_ fields: [String: Any]) async throws -> Int {
        let r = try await c.send("/reiniger", method: "POST", body: fields)
        return Coerce.int(r["id"]) ?? 0
    }

    func updateProduct(_ id: Int, _ fields: [String: Any]) async throws {
        _ = try await c.send("/reiniger/\(id)", method: "PATCH", body: fields)
    }

    func deleteProduct(_ id: Int) async throws {
        _ = try await c.send("/reiniger/\(id)", method: "DELETE")
    }
}
