import Foundation

struct BookInfo {
    let isbn: String
    var title: String?
    var authors: [String] = []
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

    static func book(isbn: String) async -> BookInfo {
        var info = BookInfo(isbn: isbn)
        guard let url = URL(string: "https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data") else { return info }
        guard let (data, _) = try? await session.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = obj["ISBN:\(isbn)"] as? [String: Any] else { return info }
        info.title = entry["title"] as? String
        if let authors = entry["authors"] as? [[String: Any]] {
            info.authors = authors.compactMap { $0["name"] as? String }
        }
        if let cover = entry["cover"] as? [String: Any] {
            info.coverURL = (cover["large"] ?? cover["medium"] ?? cover["small"]) as? String
        }
        return info
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
