import Foundation

/// Backend-Anbindung der nativen ElisBooks-App: Familienplaner v1-API (elisbooks-*) + On-Device-Metadaten
/// (Google Books / Open Library) + Proxy-Aufrufe für die KI-Features (server-seitige Endpunkte).
@MainActor
final class BooksAPI {
    private let settings: Settings
    init(settings: Settings) { self.settings = settings }

    private var base: String { settings.baseURL.hasSuffix("/") ? String(settings.baseURL.dropLast()) : settings.baseURL }
    private static let session: URLSession = {
        let c = URLSessionConfiguration.default; c.timeoutIntervalForRequest = 25; return URLSession(configuration: c)
    }()
    private static let pub: URLSession = {
        let c = URLSessionConfiguration.ephemeral; c.timeoutIntervalForRequest = 12; return URLSession(configuration: c)
    }()

    private func req(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil) throws -> URLRequest {
        guard var comps = URLComponents(string: base + "/api/v1" + path) else { throw APIError(status: 0, message: "Ungültige URL") }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError(status: 0, message: "Ungültige URL") }
        var r = URLRequest(url: url); r.httpMethod = method; r.httpBody = body
        if body != nil { r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        guard let key = settings.apiKey, !key.isEmpty else { throw APIError(status: 401, message: "Nicht angemeldet") }
        r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return r
    }

    private func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        var msg = ""
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let e = obj["error"] as? [String: Any], let m = e["message"] as? String { msg = m }
        throw APIError(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, message: msg)
    }

    private func rows(_ path: String, query: [URLQueryItem] = []) async throws -> [[String: Any]] {
        let (data, resp) = try await Self.session.data(for: req(path, query: query))
        try check(resp, data)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (obj?["data"] as? [[String: Any]]) ?? []
    }

    @discardableResult
    private func send(_ path: String, method: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        let data = body.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        let (respData, resp) = try await Self.session.data(for: req(path, method: method, body: data))
        try check(resp, respData)
        return (try? JSONSerialization.jsonObject(with: respData)) as? [String: Any] ?? [:]
    }

    // ── Bücher ──
    func fetchBooks() async throws -> [Book] {
        try await rows("/elisbooks-books", query: [URLQueryItem(name: "limit", value: "5000"), URLQueryItem(name: "sort", value: "created_at:desc")]).map(Book.init(fields:))
    }
    @discardableResult
    func createBook(_ book: Book) async throws -> Book {
        var f = book.apiFields(); f["id"] = book.id
        return Book(fields: try await send("/elisbooks-books", method: "POST", body: f))
    }
    func updateBook(_ id: String, _ fields: [String: Any]) async throws {
        _ = try await send("/elisbooks-books/\(id)", method: "PATCH", body: fields)
    }
    func deleteBook(_ id: String) async throws { _ = try await send("/elisbooks-books/\(id)", method: "DELETE") }

    // Bulk (Server-Endpunkt für Tempo; Fallback: einzeln).
    func bulk(op: String, ids: [String], extra: [String: Any] = [:]) async throws {
        guard !ids.isEmpty else { return }
        var body: [String: Any] = ["op": op, "ids": ids]
        for (k, v) in extra { body[k] = v }
        _ = try await send("/elisbooks/books-bulk", method: "POST", body: body)
    }
    func bulkMove(_ ids: [String], to shelfId: String?) async throws {
        try await bulk(op: "move", ids: ids, extra: ["bookshelf_id": shelfId as Any])
    }
    func bulkDelete(_ ids: [String]) async throws { try await bulk(op: "delete", ids: ids) }
    func bulkSetRead(_ ids: [String], _ isRead: Bool) async throws { try await bulk(op: "read", ids: ids, extra: ["is_read": isRead ? 1 : 0]) }

    // ── Regale ──
    func fetchShelves() async throws -> [Bookshelf] {
        try await rows("/elisbooks-bookshelves", query: [URLQueryItem(name: "limit", value: "200"), URLQueryItem(name: "sort", value: "name:asc")]).map(Bookshelf.init(fields:))
    }
    @discardableResult
    func createShelf(name: String, description: String?, color: String) async throws -> Bookshelf {
        var f: [String: Any] = ["id": UUID().uuidString.lowercased(), "name": name, "color": color]
        if let description, !description.isEmpty { f["description"] = description }
        return Bookshelf(fields: try await send("/elisbooks-bookshelves", method: "POST", body: f))
    }
    func updateShelf(_ id: String, name: String, description: String?, color: String? = nil) async throws {
        var f: [String: Any] = ["name": name, "description": description as Any]
        if let color { f["color"] = color }
        _ = try await send("/elisbooks-bookshelves/\(id)", method: "PATCH", body: f)
    }
    func deleteShelf(_ id: String) async throws { _ = try await send("/elisbooks-bookshelves/\(id)", method: "DELETE") }

    // ── Wunschliste ──
    func fetchWishlist() async throws -> [WishlistItem] {
        try await rows("/elisbooks-wishlist", query: [URLQueryItem(name: "limit", value: "2000"), URLQueryItem(name: "sort", value: "created_at:desc")]).map(WishlistItem.init(fields:))
    }
    @discardableResult
    func addWishlist(_ result: BookSearchResult, source: String) async throws -> WishlistItem {
        var f: [String: Any] = [
            "id": UUID().uuidString.lowercased(), "title": result.title,
            "authors": encodeStringArray(result.authors), "categories": encodeStringArray(result.categories),
            "source": source,
        ]
        if let p = result.publisher { f["publisher"] = p }
        if let d = result.publishedDate { f["published_date"] = d }
        if let d = result.description { f["description"] = d }
        if let t = result.thumbnail { f["thumbnail"] = t }
        if let i = result.isbn { f["isbn"] = i }
        return WishlistItem(fields: try await send("/elisbooks-wishlist", method: "POST", body: f))
    }
    func deleteWishlist(_ id: String) async throws { _ = try await send("/elisbooks-wishlist/\(id)", method: "DELETE") }
    func updateWishlistCover(_ id: String, _ url: String) async throws { _ = try await send("/elisbooks-wishlist/\(id)", method: "PATCH", body: ["thumbnail": url]) }

    // ── On-Device-Metadaten (Google Books + Open Library; keine Keys nötig) ──
    func searchMetadata(query: String, author: String = "", maxResults: Int = 10) async throws -> [BookSearchResult] {
        async let g = googleBooks(query: query, author: author, max: maxResults)
        async let o = openLibrary(query: query, author: author, max: maxResults)
        var out = (try? await g) ?? []
        out.append(contentsOf: (try? await o) ?? [])
        return out
    }
    func searchByISBN(_ isbn: String) async -> BookSearchResult? {
        if let g = try? await googleBooks(query: "isbn:\(isbn)", author: "", max: 1).first { return g }
        return try? await openLibraryISBN(isbn)
    }

    private func googleBooks(query: String, author: String, max: Int) async throws -> [BookSearchResult] {
        var q = query
        if !author.isEmpty && !query.hasPrefix("isbn:") { q += " inauthor:\(author)" }
        guard let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.googleapis.com/books/v1/volumes?q=\(enc)&country=DE&maxResults=\(max)") else { return [] }
        let (data, _) = try await Self.pub.data(from: url)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let vi = item["volumeInfo"] as? [String: Any], let title = vi["title"] as? String else { return nil }
            var isbn: String?
            if let ids = vi["industryIdentifiers"] as? [[String: Any]] {
                isbn = (ids.first { ($0["type"] as? String) == "ISBN_13" } ?? ids.first)?["identifier"] as? String
            }
            var thumb = (vi["imageLinks"] as? [String: Any])?["thumbnail"] as? String
            thumb = thumb?.replacingOccurrences(of: "http://", with: "https://")
            let full = (vi["subtitle"] as? String).map { "\(title): \($0)" } ?? title
            return BookSearchResult(title: full, authors: (vi["authors"] as? [String]) ?? [], publisher: vi["publisher"] as? String,
                                    publishedDate: vi["publishedDate"] as? String, description: vi["description"] as? String,
                                    pageCount: vi["pageCount"] as? Int, categories: (vi["categories"] as? [String]) ?? [],
                                    thumbnail: thumb, isbn: isbn, source: "google")
        }
    }

    private func openLibrary(query: String, author: String, max: Int) async throws -> [BookSearchResult] {
        var comps = URLComponents(string: "https://openlibrary.org/search.json")!
        comps.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: String(max))]
        if !author.isEmpty { comps.queryItems?.append(URLQueryItem(name: "author", value: author)) }
        guard let url = comps.url else { return [] }
        let (data, _) = try await Self.pub.data(from: url)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let docs = obj["docs"] as? [[String: Any]] else { return [] }
        return docs.prefix(max).compactMap { d in
            guard let title = d["title"] as? String else { return nil }
            var thumb: String?
            if let cover = d["cover_i"] as? Int { thumb = "https://covers.openlibrary.org/b/id/\(cover)-M.jpg" }
            let year = (d["first_publish_year"] as? Int).map(String.init)
            return BookSearchResult(title: title, authors: (d["author_name"] as? [String]) ?? [], publisher: (d["publisher"] as? [String])?.first,
                                    publishedDate: year, description: nil, pageCount: d["number_of_pages_median"] as? Int,
                                    categories: (d["subject"] as? [String]).map { Array($0.prefix(5)) } ?? [],
                                    thumbnail: thumb, isbn: (d["isbn"] as? [String])?.first, source: "openlibrary")
        }
    }

    private func openLibraryISBN(_ isbn: String) async throws -> BookSearchResult? {
        guard let url = URL(string: "https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data") else { return nil }
        let (data, _) = try await Self.pub.data(from: url)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let e = obj["ISBN:\(isbn)"] as? [String: Any], let title = e["title"] as? String else { return nil }
        let authors = (e["authors"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        let thumb = (e["cover"] as? [String: Any]).flatMap { ($0["large"] ?? $0["medium"] ?? $0["small"]) as? String }
        return BookSearchResult(title: title, authors: authors, publisher: (e["publishers"] as? [[String: Any]])?.first?["name"] as? String,
                                publishedDate: e["publish_date"] as? String, description: nil, pageCount: e["number_of_pages"] as? Int,
                                categories: [], thumbnail: thumb, isbn: isbn, source: "openlibrary")
    }

    // ── KI-Features (Server-Proxy; ohne OPENAI_API_KEY im Backend → 501) ──
    func aiShelfOcr(imageBase64 dataURL: String) async throws -> [[String: Any]] {
        let r = try await send("/elisbooks/ai/shelf-ocr", method: "POST", body: ["image": dataURL])
        return (r["detectedBooks"] as? [[String: Any]]) ?? []
    }
    func aiRecommendations(count: Int, timeframe: String, prompt: String, library: [[String: Any]]) async throws -> [[String: Any]] {
        let r = try await send("/elisbooks/ai/recommendations", method: "POST", body: ["count": count, "timeframe": timeframe, "customPrompt": prompt, "books": library])
        return (r["recommendations"] as? [[String: Any]]) ?? []
    }
}
