import Foundation

/// Backend-Anbindung der E-Book-Wunschliste an die Kompat-Endpunkte `/api/buecher`.
/// Nur die MIGRIERTEN Endpunkte werden genutzt: Liste (bare Array), Kategorien/Jahre (bare
/// String-Arrays), POST/PATCH/DELETE. Die externen Netz-Endpunkte (search/download/retry/enrich)
/// liefern serverseitig 501 und werden im UI deaktiviert — hier bewusst NICHT aufgerufen.
@MainActor
final class EbooksAPI {
    private let c: CompatClient
    init(settings: Settings) { c = CompatClient(settings: settings) }

    /// Wunschliste laden (bare Array). `status=alle` → Parameter weglassen.
    func fetchItems(_ f: EbookFilters) async throws -> [EbookItem] {
        var q: [URLQueryItem] = []
        if let s = f.status { q.append(.init(name: "status", value: s)) }
        if let y = f.year { q.append(.init(name: "year", value: y)) }
        if let cat = f.category { q.append(.init(name: "category", value: cat)) }
        let term = f.search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty { q.append(.init(name: "q", value: term)) }
        return try await c.getArray("/buecher", query: q).map(EbookItem.init(fields:))
    }

    /// Einzel-Eintrag frisch laden.
    func fetchItem(_ id: Int) async throws -> EbookItem {
        EbookItem(fields: try await c.getObject("/buecher/\(id)"))
    }

    /// Distinct-Kategorien (aufsteigend) für das Dropdown.
    func fetchCategories() async throws -> [String] {
        try await c.getStrings("/buecher", query: [.init(name: "categories", value: "true")])
    }

    /// Distinct-Jahre (absteigend) für das Dropdown.
    func fetchYears() async throws -> [String] {
        try await c.getStrings("/buecher", query: [.init(name: "years", value: "true")])
    }

    /// Manuelles Anlegen — POST funktioniert offline (kein externer Dienst).
    @discardableResult
    func createItem(_ fields: [String: Any]) async throws -> Int {
        let r = try await c.send("/buecher", method: "POST", body: fields)
        return Coerce.int(r["id"]) ?? 0
    }

    /// Teil-Update (18-Feld-Whitelist serverseitig; unbekannte Keys werden ignoriert).
    func updateItem(_ id: Int, _ fields: [String: Any]) async throws {
        _ = try await c.send("/buecher/\(id)", method: "PATCH", body: fields)
    }

    func deleteItem(_ id: Int) async throws {
        _ = try await c.send("/buecher/\(id)", method: "DELETE")
    }

    // MARK: - Externe Suche (Shelfmark)

    /// Externe Buchsuche über Shelfmark (GET /api/buecher/search?q=…).
    func searchExternal(_ query: String) async throws -> [ShelfmarkResult] {
        let obj = try await c.getObject("/buecher/search", query: [.init(name: "q", value: query)])
        let arr = (obj["results"] as? [[String: Any]]) ?? []
        return arr.map(ShelfmarkResult.init(fields:))
    }

    /// Download starten (addOnly=false) oder nur auf die Wunschliste setzen (addOnly=true).
    @discardableResult
    func download(_ raw: [String: Any], addOnly: Bool) async throws -> [String: Any] {
        try await c.send("/buecher/download", method: "POST", body: ["release": raw, "addOnly": addOnly])
    }
}
