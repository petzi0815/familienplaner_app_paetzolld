import Foundation

/// Backend-Anbindung des Samu-Inventars an die Kompat-Endpunkte `/api/items|marken|bedarf`.
@MainActor
final class SamuAPI {
    private let c: CompatClient
    init(settings: Settings) { c = CompatClient(settings: settings) }

    // ── Items ──
    func fetchItems(_ f: SamuFilters) async throws -> [SamuItem] {
        var q: [URLQueryItem] = []
        if let s = f.status { q.append(.init(name: "status", value: s)) }
        if let t = f.typ { q.append(.init(name: "typ", value: t)) }
        if let k = f.kategorie { q.append(.init(name: "kategorie", value: k)) }
        if let g = f.groesse { q.append(.init(name: "groesse", value: g)) }
        if !f.search.isEmpty { q.append(.init(name: "search", value: f.search)) }
        return try await c.getArray("/items", query: q).map(SamuItem.init(fields:))
    }

    func fetchItem(_ id: Int) async throws -> SamuItem {
        SamuItem(fields: try await c.getObject("/items/\(id)"))
    }

    func fetchStats() async throws -> SamuStats {
        SamuStats(object: try await c.getObject("/items", query: [.init(name: "stats", value: "true")]))
    }

    func fetchMatrix() async throws -> [SamuMatrixCell] {
        try await c.getArray("/items", query: [.init(name: "matrix", value: "true")]).compactMap(SamuMatrixCell.init)
    }

    func fetchKategorien(status: String?, typ: String?) async throws -> [String] {
        var q: [URLQueryItem] = [.init(name: "kategorien", value: "true")]
        if let s = status { q.append(.init(name: "status", value: s)) }
        if let t = typ { q.append(.init(name: "typ", value: t)) }
        return try await c.getStrings("/items", query: q)
    }

    func fetchGroessen(status: String?, typ: String?) async throws -> [String] {
        var q: [URLQueryItem] = [.init(name: "groessen", value: "true")]
        if let s = status { q.append(.init(name: "status", value: s)) }
        if let t = typ { q.append(.init(name: "typ", value: t)) }
        return try await c.getStrings("/items", query: q)
    }

    /// Teil-Update (nur die editierbaren Felder werden übergeben).
    func updateItem(_ id: Int, _ fields: [String: Any]) async throws {
        _ = try await c.send("/items/\(id)", method: "PUT", body: fields)
    }

    // ── Marken ──
    func fetchMarken() async throws -> [SamuMarke] {
        try await c.getArray("/marken").map(SamuMarke.init(fields:))
    }

    // ── Bedarf ──
    func fetchBedarf(erledigt: Int? = nil) async throws -> [SamuBedarf] {
        var q: [URLQueryItem] = []
        if let e = erledigt { q.append(.init(name: "erledigt", value: String(e))) }
        return try await c.getArray("/bedarf", query: q).map(SamuBedarf.init(fields:))
    }

    @discardableResult
    func addBedarf(beschreibung: String, kategorie: String?, groesse: String?, prioritaet: String, notizen: String?) async throws -> Int {
        var body: [String: Any] = ["beschreibung": beschreibung, "prioritaet": prioritaet]
        if let k = kategorie, !k.isEmpty { body["kategorie"] = k }
        if let g = groesse, !g.isEmpty { body["groesse"] = g }
        if let n = notizen, !n.isEmpty { body["notizen"] = n }
        let r = try await c.send("/bedarf", method: "POST", body: body)
        return Coerce.int(r["id"]) ?? 0
    }

    func setBedarfErledigt(_ id: Int, _ done: Bool) async throws {
        _ = try await c.send("/bedarf/\(id)", method: "PATCH", body: ["erledigt": done ? 1 : 0])
    }

    func deleteBedarf(_ id: Int) async throws {
        _ = try await c.send("/bedarf/\(id)", method: "DELETE")
    }
}
