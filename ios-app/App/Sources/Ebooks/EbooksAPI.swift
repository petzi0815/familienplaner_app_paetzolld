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

    // MARK: - Wunschlisten-Retry (Shelfmark)

    /// Ein Buch prüfen + laden. Antwort: { found, downloaded, message }.
    @discardableResult
    func wishlistCheck(_ id: Int) async throws -> [String: Any] {
        try await c.send("/buecher/wishlist-check", method: "POST", body: ["id": id])
    }

    /// Alle „gesucht"-Bücher im Hintergrund prüfen. Gibt die Anzahl offener zurück.
    func wishlistCheckAll() async throws -> Int {
        let r = try await c.send("/buecher/wishlist-check-all", method: "POST")
        return Coerce.int(r["pending"]) ?? 0
    }

    /// Erfolgreich heruntergeladene Bücher entfernen. Gibt die Anzahl gelöschter zurück.
    @discardableResult
    func wishlistCleanup() async throws -> Int {
        let r = try await c.send("/buecher/wishlist-cleanup", method: "POST")
        return Coerce.int(r["deleted"]) ?? 0
    }

    // MARK: - Calibre-Web (Bibliothek)

    func calibreShelves() async throws -> [CalibreShelf] {
        let obj = try await c.getObject("/buecher/calibre/shelves")
        return ((obj["shelves"] as? [[String: Any]]) ?? []).compactMap(CalibreShelf.init)
    }

    /// Bücher listen/suchen ODER (shelf gesetzt) Regal-Inhalt; mit Sortierung.
    func calibreBooks(search: String?, shelf: Int?, offset: Int, limit: Int = 60,
                      sort: String? = nil, order: String? = nil) async throws -> (total: Int, rows: [CalibreBook]) {
        var q: [URLQueryItem] = [.init(name: "offset", value: String(offset)), .init(name: "limit", value: String(limit))]
        if let s = search, !s.isEmpty { q.append(.init(name: "search", value: s)) }
        if let sh = shelf { q.append(.init(name: "shelf", value: String(sh))) }
        if let sort { q.append(.init(name: "sort", value: sort)) }
        if let order { q.append(.init(name: "order", value: order)) }
        let obj = try await c.getObject("/buecher/calibre/books", query: q)
        let rows = ((obj["rows"] as? [[String: Any]]) ?? []).map(CalibreBook.init(fields:))
        return (Coerce.int(obj["total"]) ?? rows.count, rows)
    }

    /// Detail: zugeordnete Regal-IDs + (soweit ermittelbar) Voll-Metadaten + herunterladbare Formate.
    func calibreBookDetail(id: Int, title: String?) async throws -> (shelfIds: [Int], book: CalibreBook?, formats: [String]) {
        var q: [URLQueryItem] = []
        if let t = title, !t.isEmpty { q.append(.init(name: "title", value: t)) }
        let obj = try await c.getObject("/buecher/calibre/book/\(id)", query: q)
        let ids = (obj["shelf_ids"] as? [Any])?.compactMap { Coerce.int($0) } ?? []
        let book = (obj["book"] as? [String: Any]).map(CalibreBook.init(fields:))
        let formats = (obj["formats"] as? [Any])?.compactMap { Coerce.str($0) } ?? []
        return (ids, book, formats)
    }

    /// Buch-Datei (epub/…) aus Calibre laden — Roh-Bytes zum Speichern/Teilen (→ Apple Books).
    func calibreDownload(id: Int, format: String) async throws -> Data {
        try await c.downloadData("/buecher/calibre/download/\(id)", query: [.init(name: "format", value: format)])
    }

    @discardableResult
    func calibreShelfAction(bookId: Int, shelfId: Int, action: String) async throws -> Bool {
        let r = try await c.send("/buecher/calibre/shelf", method: "POST", body: ["book_id": bookId, "shelf_id": shelfId, "action": action])
        return Coerce.bool(r["success"])
    }
}
