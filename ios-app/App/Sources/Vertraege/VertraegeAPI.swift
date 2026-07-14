import Foundation

/// Anbindung des Verträge-Bereichs an die generische v1-Ressource `/api/v1/vertraege`.
/// WICHTIG: v1 liefert einen ENVELOPE `{data:[…],total,limit,offset}` (kein bares Array).
/// CompatClient stellt `/api` voran → Pfade beginnen hier mit `/v1/…`.
@MainActor
final class VertraegeAPI {
    private let c: CompatClient
    init(settings: Settings) { c = CompatClient(settings: settings) }

    /// Alle Verträge (bis 500) — Envelope, `.data` entpacken.
    func fetchAll() async throws -> [Vertrag] {
        let obj = try await c.getObject("/v1/vertraege", query: [
            URLQueryItem(name: "limit", value: "500"),
            URLQueryItem(name: "sort", value: "id:desc"),
        ])
        let rows = (obj["data"] as? [[String: Any]]) ?? []
        return rows.map(Vertrag.init(fields:))
    }

    /// Einzelner Vertrag (bares Objekt, KEIN Envelope).
    func fetchOne(_ id: Int) async throws -> Vertrag {
        Vertrag(fields: try await c.getObject("/v1/vertraege/\(id)"))
    }

    @discardableResult
    func create(_ body: [String: Any]) async throws -> Vertrag {
        Vertrag(fields: try await c.send("/v1/vertraege", method: "POST", body: body))
    }

    @discardableResult
    func update(_ id: Int, _ body: [String: Any]) async throws -> Vertrag {
        Vertrag(fields: try await c.send("/v1/vertraege/\(id)", method: "PATCH", body: body))
    }

    func delete(_ id: Int) async throws {
        _ = try await c.send("/v1/vertraege/\(id)", method: "DELETE")
    }
}
