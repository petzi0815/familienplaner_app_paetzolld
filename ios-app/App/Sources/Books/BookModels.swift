import Foundation

// Native ElisBooks-Modelle. Backend = Familienplaner v1-API (elisbooks-books/-bookshelves/-wishlist).
// WICHTIG: die v1-API liefert JSON-Array-Spalten (authors/categories) als JSON-STRING (TEXT-Spalte).
// Deshalb dekodieren wir tolerant: entweder [String] ODER ein JSON-String '["a","b"]'.

func decodeStringArray(_ raw: Any?) -> [String] {
    if let arr = raw as? [String] { return arr }
    if let arr = raw as? [Any] { return arr.compactMap { $0 as? String } }
    if let s = raw as? String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t == "[]" { return [] }
        if let data = t.data(using: .utf8), let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return arr.compactMap { $0 as? String }
        }
        return [t]
    }
    return []
}

func encodeStringArray(_ arr: [String]) -> String {
    (try? JSONSerialization.data(withJSONObject: arr)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
}

private func asInt(_ v: Any?) -> Int? {
    if let i = v as? Int { return i }
    if let d = v as? Double { return Int(d) }
    if let n = v as? NSNumber { return n.intValue }
    if let s = v as? String { return Int(s) }
    return nil
}
private func asBool(_ v: Any?) -> Bool {
    if let b = v as? Bool { return b }
    if let i = asInt(v) { return i != 0 }
    if let s = v as? String { return ["1", "true", "ja", "yes"].contains(s.lowercased()) }
    return false
}
private func asStr(_ v: Any?) -> String? {
    if let s = v as? String { return s.isEmpty ? nil : s }
    if v is NSNull || v == nil { return nil }
    return String(describing: v!)
}

// ── Buch ──
struct Book: Identifiable, Equatable {
    var id: String
    var isbn: String?
    var title: String
    var authors: [String]
    var publisher: String?
    var publishedDate: String?
    var description: String?
    var pageCount: Int?
    var categories: [String]
    var thumbnail: String?
    var language: String?
    var bookshelfId: String?
    var isRead: Bool
    var isOnPicklist: Bool
    var addedAt: String?

    init(fields f: [String: Any]) {
        id = asStr(f["id"]) ?? UUID().uuidString
        isbn = asStr(f["isbn"])
        title = asStr(f["title"]) ?? "Unbekannter Titel"
        authors = decodeStringArray(f["authors"])
        publisher = asStr(f["publisher"])
        publishedDate = asStr(f["published_date"])
        description = asStr(f["description"])
        pageCount = asInt(f["page_count"])
        categories = decodeStringArray(f["categories"])
        thumbnail = asStr(f["thumbnail"])
        language = asStr(f["language"])
        bookshelfId = asStr(f["bookshelf_id"])
        isRead = asBool(f["is_read"])
        isOnPicklist = asBool(f["is_on_picklist"])
        addedAt = asStr(f["added_at"]) ?? asStr(f["created_at"])
    }

    var authorText: String { authors.isEmpty ? "Unbekannter Autor" : authors.joined(separator: ", ") }
    var yearInt: Int? {
        guard let d = publishedDate, let m = d.range(of: "[0-9]{4}", options: .regularExpression) else { return nil }
        return Int(d[m])
    }
    var hasValidCover: Bool { (thumbnail?.isEmpty == false) }

    /// Feld-Payload für die v1-API (JSON-Spalten als String).
    func apiFields() -> [String: Any] {
        var d: [String: Any] = [
            "title": title,
            "authors": encodeStringArray(authors),
            "categories": encodeStringArray(categories),
            "language": language ?? "de",
            "publisher": publisher ?? "Unbekannter Verlag",
            "is_read": isRead ? 1 : 0,
            "is_on_picklist": isOnPicklist ? 1 : 0,
        ]
        if let isbn { d["isbn"] = isbn }
        if let publishedDate { d["published_date"] = publishedDate }
        if let description { d["description"] = description }
        if let pageCount, pageCount > 0 { d["page_count"] = pageCount }
        if let thumbnail { d["thumbnail"] = thumbnail }
        if let bookshelfId { d["bookshelf_id"] = bookshelfId }
        return d
    }
}

// ── Regal ──
struct Bookshelf: Identifiable, Equatable {
    var id: String
    var name: String
    var description: String?
    var color: String

    init(fields f: [String: Any]) {
        id = asStr(f["id"]) ?? UUID().uuidString
        name = asStr(f["name"]) ?? "Regal"
        description = asStr(f["description"])
        color = asStr(f["color"]) ?? "#3B82F6"
    }
    init(id: String, name: String, description: String?, color: String) {
        self.id = id; self.name = name; self.description = description; self.color = color
    }
}

// ── Wunschlisten-Eintrag ──
struct WishlistItem: Identifiable, Equatable {
    var id: String
    var title: String
    var authors: [String]
    var publisher: String?
    var publishedDate: String?
    var description: String?
    var categories: [String]
    var thumbnail: String?
    var isbn: String?
    var source: String

    init(fields f: [String: Any]) {
        id = asStr(f["id"]) ?? UUID().uuidString
        title = asStr(f["title"]) ?? "Unbekannter Titel"
        authors = decodeStringArray(f["authors"])
        publisher = asStr(f["publisher"])
        publishedDate = asStr(f["published_date"])
        description = asStr(f["description"])
        categories = decodeStringArray(f["categories"])
        thumbnail = asStr(f["thumbnail"])
        isbn = asStr(f["isbn"])
        source = asStr(f["source"]) ?? "manual"
    }
    var authorText: String { authors.isEmpty ? "Unbekannter Autor" : authors.joined(separator: ", ") }
}

// ── Metadaten-Suchergebnis (Google Books / Open Library / …) ──
struct BookSearchResult: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var authors: [String]
    var publisher: String?
    var publishedDate: String?
    var description: String?
    var pageCount: Int?
    var categories: [String]
    var thumbnail: String?
    var isbn: String?
    var source: String   // google | openlibrary | worldcat | …
    var authorText: String { authors.isEmpty ? "Unbekannter Autor" : authors.joined(separator: ", ") }

    func toBook(bookshelfId: String?) -> Book {
        var f: [String: Any] = [
            "title": title, "authors": authors, "categories": categories,
            "language": "de", "is_read": 0, "is_on_picklist": 0,
        ]
        if let isbn { f["isbn"] = isbn }
        if let publisher { f["publisher"] = publisher }
        if let publishedDate { f["published_date"] = publishedDate }
        if let description { f["description"] = description }
        if let pageCount { f["page_count"] = pageCount }
        if let thumbnail { f["thumbnail"] = thumbnail }
        if let bookshelfId { f["bookshelf_id"] = bookshelfId }
        var b = Book(fields: f)
        b.id = UUID().uuidString.lowercased()
        return b
    }
}

// ── Views (Navigationsziele) ──
enum BooksView: String, CaseIterable, Identifiable {
    case shelves, books, wishlist, scanner, manual, bulkScanner = "bulk-scanner", shelfScanner = "shelf-scanner", similar, ocrScanner = "ocr-scanner"
    var id: String { rawValue }
}

// ── Filter ──
enum ReadStatus: String, CaseIterable { case all, read, unread }
enum SortField: String, CaseIterable, Identifiable {
    case title, author, added, year
    var id: String { rawValue }
    var label: String { switch self { case .title: return "Titel"; case .author: return "Autor"; case .added: return "Hinzugefügt"; case .year: return "Erscheinungsjahr" } }
}

struct BookFilters: Equatable {
    var searchTerm = ""
    var bookshelf: String = "all"       // "all" | shelf id
    var publisher: String = "all"
    var language: String = "all"
    var category: String = "all"
    var yearFrom: Int? = nil
    var yearTo: Int? = nil
    var readStatus: ReadStatus = .all
    var hasDescription: Bool? = nil
    var hasThumbnail: Bool? = nil
    var picklistOnly = false
    var sort: SortField = .title
    var sortAsc = true

    var activeCount: Int {
        var n = 0
        if !searchTerm.isEmpty { n += 1 }
        if bookshelf != "all" { n += 1 }
        if publisher != "all" { n += 1 }
        if language != "all" { n += 1 }
        if category != "all" { n += 1 }
        if yearFrom != nil || yearTo != nil { n += 1 }
        if readStatus != .all { n += 1 }
        if hasDescription != nil { n += 1 }
        if hasThumbnail != nil { n += 1 }
        if picklistOnly { n += 1 }
        return n
    }

    static let languageMap: [String: String] = ["de": "Deutsch", "en": "Englisch", "fr": "Französisch", "es": "Spanisch"]
    static func languageLabel(_ code: String) -> String { languageMap[code] ?? code }
}

// Regal-Farbpalette (wie Original).
let SHELF_COLORS: [String] = ["#3B82F6", "#10B981", "#8B5CF6", "#EF4444", "#F59E0B", "#6366F1"]
let SHELF_COLOR_NAMES: [(String, String)] = [("#3B82F6", "Blau"), ("#10B981", "Grün"), ("#8B5CF6", "Lila"), ("#EF4444", "Rot"), ("#F59E0B", "Gelb"), ("#6366F1", "Indigo")]
