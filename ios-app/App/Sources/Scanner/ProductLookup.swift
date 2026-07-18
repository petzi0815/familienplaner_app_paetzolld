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
    var quantity: String?          // z.B. "400 g" (OFF `quantity`)
    var categoryTags: [String] = [] // OFF `categories_tags` (en:-Tags) → Lagerort-Heuristik
    var imageURL: String?          // Produkt-Frontbild (OFF) — als Foto-Vorschlag
    var found: Bool = false
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

    /// Lebensmittel-Metadaten via Open Food Facts (öffentlich, kein Key, keine Limits). Liefert Name (de
    /// bevorzugt), Marke, Menge, Kategorie-Tags (für die Lagerort-Heuristik) und ein Produktbild.
    static func food(ean: String) async -> FoodInfo {
        var info = FoodInfo()
        let fields = "product_name,product_name_de,brands,quantity,categories_tags,image_front_small_url,image_front_url,image_url"
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(ean).json?fields=\(fields)") else { return info }
        guard let (data, _) = try? await session.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["status"] as? Int) == 1,
              let product = obj["product"] as? [String: Any] else { return info }
        info.found = true
        info.name = (product["product_name_de"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (product["product_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        info.brand = (product["brands"] as? String)?.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) }
        info.quantity = (product["quantity"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        info.categoryTags = (product["categories_tags"] as? [String]) ?? []
        info.imageURL = ((product["image_front_small_url"] ?? product["image_front_url"] ?? product["image_url"]) as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
        return info
    }

    /// Heuristische Lagerort-Zuordnung aus den OFF-Kategorien: Tiefkühl > Kühlschrank > Regal (Default).
    /// Nur ein Vorschlag — der Nutzer kann den Lagerort im Formular ändern.
    static func lagerort(categoryTags tags: [String]) -> String {
        let s = tags.joined(separator: " ").lowercased()
        let frozen = ["frozen", "ice-cream", "ice cream", "tiefkuhl", "tiefkühl", "gefror", "surgel"]
        let fridge = ["dair", "milk", "yogurt", "yoghurt", "cheese", "butter", "cream", "quark",
                      "fresh", "chilled", "refrigerat", "meat", "poultry", "sausage", "charcuterie",
                      "ham", "fish", "seafood", "egg", "tofu", "deli", "wurst", "kase", "käse"]
        if frozen.contains(where: { s.contains($0) }) { return "gefrierfach" }
        if fridge.contains(where: { s.contains($0) }) { return "kuehlschrank" }
        return "trocken"
    }
}
