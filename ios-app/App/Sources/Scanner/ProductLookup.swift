import Foundation

struct BookInfo {
    let isbn: String
    var title: String?
    var authors: [String] = []
    var publisher: String?
    var publishedDate: String?
    var description: String?
    var pageCount: Int?
    var categories: [String] = []
    var language: String?
    var coverURL: String?
}
struct FoodInfo {
    var name: String?
    var brand: String?
}

/// Öffentliche Kataloge (kein Auth): Open Library für Bücher, Open Food Facts für Lebensmittel.
/// Best-effort — bei Fehlschlag trägt der Nutzer die Felder selbst nach.
enum ProductLookup {
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 12
        return URLSession(configuration: c)
    }()

    /// Bücher-Metadaten: zuerst Google Books (reich: Verlag/Datum/Beschreibung/Seiten/Kategorien/Sprache/Cover —
    /// wie die Bücher-App), Open Library als Fallback für Titel/Autor/Cover. Best-effort.
    static func book(isbn: String) async -> BookInfo {
        var info = BookInfo(isbn: isbn)
        await enrichGoogleBooks(&info)
        if info.title == nil || info.title?.isEmpty == true { await enrichOpenLibrary(&info) }
        else if info.coverURL == nil { await enrichOpenLibrary(&info, coverOnly: true) }
        return info
    }

    private static func enrichGoogleBooks(_ info: inout BookInfo) async {
        guard let url = URL(string: "https://www.googleapis.com/books/v1/volumes?q=isbn:\(info.isbn)&country=DE&maxResults=1") else { return }
        guard let (data, _) = try? await session.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["items"] as? [[String: Any]],
              let vi = items.first?["volumeInfo"] as? [String: Any] else { return }
        if let t = vi["title"] as? String {
            info.title = (vi["subtitle"] as? String).map { "\(t): \($0)" } ?? t
        }
        info.authors = (vi["authors"] as? [String]) ?? info.authors
        info.publisher = vi["publisher"] as? String
        info.publishedDate = vi["publishedDate"] as? String
        info.description = vi["description"] as? String
        info.pageCount = vi["pageCount"] as? Int
        info.categories = (vi["categories"] as? [String]) ?? []
        info.language = vi["language"] as? String
        if let links = vi["imageLinks"] as? [String: Any],
           let thumb = (links["thumbnail"] ?? links["smallThumbnail"]) as? String {
            info.coverURL = thumb.replacingOccurrences(of: "http://", with: "https://")
        }
    }

    private static func enrichOpenLibrary(_ info: inout BookInfo, coverOnly: Bool = false) async {
        guard let url = URL(string: "https://openlibrary.org/api/books?bibkeys=ISBN:\(info.isbn)&format=json&jscmd=data") else { return }
        guard let (data, _) = try? await session.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = obj["ISBN:\(info.isbn)"] as? [String: Any] else { return }
        if let cover = entry["cover"] as? [String: Any] {
            info.coverURL = info.coverURL ?? ((cover["large"] ?? cover["medium"] ?? cover["small"]) as? String)
        }
        if coverOnly { return }
        info.title = info.title ?? (entry["title"] as? String)
        if info.authors.isEmpty, let authors = entry["authors"] as? [[String: Any]] {
            info.authors = authors.compactMap { $0["name"] as? String }
        }
        if info.publisher == nil, let pubs = entry["publishers"] as? [[String: Any]] {
            info.publisher = pubs.first?["name"] as? String
        }
        if info.publishedDate == nil { info.publishedDate = entry["publish_date"] as? String }
        if info.pageCount == nil { info.pageCount = entry["number_of_pages"] as? Int }
    }

    static func food(ean: String) async -> FoodInfo {
        var info = FoodInfo()
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(ean).json?fields=product_name,product_name_de,brands") else { return info }
        guard let (data, _) = try? await session.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["status"] as? Int) == 1,
              let product = obj["product"] as? [String: Any] else { return info }
        info.name = (product["product_name_de"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (product["product_name"] as? String)
        info.brand = (product["brands"] as? String)?.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) }
        return info
    }
}
