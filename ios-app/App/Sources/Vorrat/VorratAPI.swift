import Foundation

/// Backend-Anbindung der Vorratskammer an die Kompat-Endpunkte `/api/vorratskammer(+/rezepte)`.
/// Query-„Modi" sind exklusiv & precedence-geordnet (stats > einkaufsliste > ablaufend > Liste) —
/// daher vier separate GETs für die vier Sichten (wie die Original-Seite).
@MainActor
final class VorratAPI {
    private let c: CompatClient
    init(settings: Settings) { c = CompatClient(settings: settings) }

    // ── Lesen ──

    /// Aktive/gefilterte Liste (bare Array, Server sortiert `erfasst_am DESC`).
    func fetchItems(status: String?, search: String) async throws -> [VorratItem] {
        var q: [URLQueryItem] = []
        if let s = status { q.append(.init(name: "status", value: s)) }
        if !search.isEmpty { q.append(.init(name: "search", value: search)) }
        return try await c.getArray("/vorratskammer", query: q).map(VorratItem.init(fields:))
    }

    /// Stats-Objekt (`?stats=true`).
    func fetchStats() async throws -> VorratStats {
        VorratStats(object: try await c.getObject("/vorratskammer", query: [.init(name: "stats", value: "true")]))
    }

    /// Einkaufsliste = `status='verbraucht' AND restock=1` (bare Array, sortiert name ASC).
    func fetchEinkauf() async throws -> [VorratItem] {
        try await c.getArray("/vorratskammer", query: [.init(name: "einkaufsliste", value: "true")]).map(VorratItem.init(fields:))
    }

    /// Bald ablaufend (aktiv, MHD ≤ heute+`tage`, sortiert mhd ASC).
    func fetchAblaufend(tage: Int = 14) async throws -> [VorratItem] {
        let q: [URLQueryItem] = [.init(name: "ablaufend", value: "true"), .init(name: "tage", value: String(tage))]
        return try await c.getArray("/vorratskammer", query: q).map(VorratItem.init(fields:))
    }

    /// Rezeptvorschläge (bare Array, Server sortiert `erstellt_am DESC`).
    func fetchRezepte() async throws -> [VorratRezept] {
        try await c.getArray("/vorratskammer/rezepte").map(VorratRezept.init(fields:))
    }

    // ── Schreiben (Agent-Rolle) ──

    @discardableResult
    func create(_ fields: [String: Any]) async throws -> Int {
        let r = try await c.send("/vorratskammer", method: "POST", body: fields)
        return Coerce.int(r["id"]) ?? 0
    }

    func update(_ id: Int, _ fields: [String: Any]) async throws {
        _ = try await c.send("/vorratskammer/\(id)", method: "PATCH", body: fields)
    }

    func delete(_ id: Int) async throws {
        _ = try await c.send("/vorratskammer/\(id)", method: "DELETE")
    }

    /// Bild hochladen → storage_key (für `bild_pfad`). Nutzt den v1-Media-Endpunkt via CompatClient.
    func uploadPhoto(jpeg: Data) async throws -> String? {
        let payload: [String: Any] = [
            "area": "vorrat", "filename": "foto.jpg", "mime": "image/jpeg",
            "data_base64": jpeg.base64EncodedString(),
        ]
        return try await c.send("/v1/media/upload", method: "POST", body: payload)["storage_key"] as? String
    }
}
