import SwiftUI

/// Zentraler Zustand der nativen ElisBooks-App (Bücher, Regale, Wunschliste, Filter, Auswahl).
@MainActor
final class BooksStore: ObservableObject {
    let api: BooksAPI

    @Published var books: [Book] = []
    @Published var shelves: [Bookshelf] = []
    @Published var wishlist: [WishlistItem] = []

    @Published var currentView: BooksView = .shelves
    @Published var activeShelf: String? = nil
    @Published var filters = BookFilters()
    @Published var selection: Set<String> = []
    @Published var selectionMode = false

    @Published var loading = true
    @Published var message: String? = nil
    @Published var messageIsError = false

    init(settings: Settings) { self.api = BooksAPI(settings: settings) }

    // ── Laden ──
    func loadAll() async {
        loading = true
        books = (try? await api.fetchBooks()) ?? books
        shelves = (try? await api.fetchShelves()) ?? shelves
        wishlist = (try? await api.fetchWishlist()) ?? wishlist
        autoSelectShelf()
        loading = false
    }

    private func autoSelectShelf() {
        guard activeShelf == nil else {
            if !shelves.contains(where: { $0.id == activeShelf }) { activeShelf = shelves.first?.id }
            return
        }
        if shelves.count == 1 { activeShelf = shelves.first?.id }
        else if shelves.count > 1 { activeShelf = shelves.first?.id }
    }

    func shelf(_ id: String?) -> Bookshelf? { shelves.first { $0.id == id } }
    func bookCount(shelf id: String) -> Int { books.filter { $0.bookshelfId == id }.count }

    // ── Filter/Sortierung ──
    var filteredBooks: [Book] {
        var out = books
        let f = filters
        if f.bookshelf != "all" { out = out.filter { $0.bookshelfId == f.bookshelf } }
        if f.publisher != "all" { out = out.filter { ($0.publisher ?? "") == f.publisher } }
        if f.language != "all" { out = out.filter { ($0.language ?? "") == f.language } }
        if f.category != "all" { out = out.filter { $0.categories.contains(f.category) } }
        if f.readStatus == .read { out = out.filter { $0.isRead } }
        if f.readStatus == .unread { out = out.filter { !$0.isRead } }
        if let hd = f.hasDescription { out = out.filter { ($0.description?.isEmpty == false) == hd } }
        if let ht = f.hasThumbnail { out = out.filter { $0.hasValidCover == ht } }
        if f.picklistOnly { out = out.filter { $0.isOnPicklist } }
        if let yf = f.yearFrom { out = out.filter { ($0.yearInt ?? 0) >= yf } }
        if let yt = f.yearTo { out = out.filter { ($0.yearInt ?? 9999) <= yt } }
        if !f.searchTerm.isEmpty {
            let q = f.searchTerm.lowercased()
            out = out.filter {
                $0.title.lowercased().contains(q) || $0.authorText.lowercased().contains(q)
                    || ($0.publisher ?? "").lowercased().contains(q) || ($0.description ?? "").lowercased().contains(q)
            }
        }
        out.sort { a, b in
            let asc = f.sortAsc
            switch f.sort {
            case .title: return cmp(a.title, b.title, asc)
            case .author: return cmp(a.authors.first ?? "", b.authors.first ?? "", asc)
            case .added: return cmp(a.addedAt ?? "", b.addedAt ?? "", asc)
            case .year: return asc ? (a.yearInt ?? 0) < (b.yearInt ?? 0) : (a.yearInt ?? 0) > (b.yearInt ?? 0)
            }
        }
        return out
    }
    private func cmp(_ a: String, _ b: String, _ asc: Bool) -> Bool {
        let r = a.localizedCaseInsensitiveCompare(b)
        return asc ? r == .orderedAscending : r == .orderedDescending
    }

    var availablePublishers: [String] { Array(Set(books.compactMap { $0.publisher }).filter { !$0.isEmpty }).sorted() }
    var availableLanguages: [String] { Array(Set(books.compactMap { $0.language }).filter { !$0.isEmpty }).sorted() }
    var availableCategories: [String] { Array(Set(books.flatMap { $0.categories }).filter { !$0.isEmpty }).sorted() }
    var yearBounds: (Int, Int)? {
        let ys = books.compactMap { $0.yearInt }.filter { $0 > 1000 }
        guard let mn = ys.min(), let mx = ys.max() else { return nil }
        return (mn, mx)
    }
    var picklistCount: Int { books.filter { $0.isOnPicklist }.count }

    // ── Auswahl ──
    func toggleSelect(_ id: String) {
        if !selectionMode { selectionMode = true }
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
    func endSelection() { selectionMode = false; selection.removeAll() }
    func selectAllFiltered() { selection = Set(filteredBooks.map { $0.id }) }

    // ── Buch-Operationen (optimistisch) ──
    private func patchLocal(_ id: String, _ mutate: (inout Book) -> Void) {
        if let i = books.firstIndex(where: { $0.id == id }) { mutate(&books[i]) }
    }

    func toggleRead(_ book: Book) async {
        let nv = !book.isRead
        patchLocal(book.id) { $0.isRead = nv }
        try? await api.updateBook(book.id, ["is_read": nv ? 1 : 0])
    }
    func togglePicklist(_ book: Book) async {
        let nv = !book.isOnPicklist
        patchLocal(book.id) { $0.isOnPicklist = nv }
        try? await api.updateBook(book.id, ["is_on_picklist": nv ? 1 : 0])
        notify(nv ? "Zur Pickliste hinzugefügt" : "Von Pickliste entfernt")
    }
    func updateBookFields(_ id: String, _ fields: [String: Any]) async {
        do { try await api.updateBook(id, fields); await reloadBooks() }
        catch { notify(errText(error), error: true) }
    }
    func moveBook(_ id: String, to shelfId: String?) async {
        patchLocal(id) { $0.bookshelfId = shelfId }
        try? await api.updateBook(id, ["bookshelf_id": shelfId as Any])
    }
    func deleteBooks(_ ids: [String]) async {
        books.removeAll { ids.contains($0.id) }
        do { try await api.bulkDelete(ids) } catch { await reloadBooks() }
        selection.subtract(ids)
    }

    func addBook(_ book: Book) async -> Bool {
        do {
            let created = try await api.createBook(book)
            books.insert(created, at: 0)
            notify("Buch hinzugefügt")
            return true
        } catch { notify(errText(error), error: true); return false }
    }

    // ── Bulk ──
    func bulkMove(to shelfId: String?) async {
        let ids = Array(selection)
        for id in ids { patchLocal(id) { $0.bookshelfId = shelfId } }
        try? await api.bulkMove(ids, to: shelfId); notify("\(ids.count) verschoben"); endSelection()
    }
    func bulkSetRead(_ read: Bool) async {
        let ids = Array(selection)
        for id in ids { patchLocal(id) { $0.isRead = read } }
        try? await api.bulkSetRead(ids, read); notify(read ? "Als gelesen markiert" : "Als ungelesen markiert"); endSelection()
    }
    func bulkDelete() async {
        let ids = Array(selection); await deleteBooks(ids); notify("\(ids.count) gelöscht"); endSelection()
    }

    // ── Regale ──
    func createShelf(name: String, description: String?, color: String) async {
        do { let s = try await api.createShelf(name: name, description: description, color: color); shelves.append(s); shelves.sort { $0.name < $1.name }; if activeShelf == nil { activeShelf = s.id }; notify("Regal erstellt!") }
        catch { notify(errText(error), error: true) }
    }
    func updateShelf(_ id: String, name: String, description: String?, color: String? = nil) async {
        do { try await api.updateShelf(id, name: name, description: description, color: color); await reloadShelves() }
        catch { notify(errText(error), error: true) }
    }
    func deleteShelf(_ id: String, transferTo: String?) async {
        let affected = books.filter { $0.bookshelfId == id }.map { $0.id }
        if let target = transferTo, !affected.isEmpty { try? await api.bulkMove(affected, to: target) }
        do { try await api.deleteShelf(id); shelves.removeAll { $0.id == id }; if activeShelf == id { activeShelf = shelves.first?.id }; await reloadBooks() }
        catch { notify(errText(error), error: true) }
    }

    // ── Wunschliste ──
    func addToWishlist(_ r: BookSearchResult, source: String) async {
        do { let w = try await api.addWishlist(r, source: source); wishlist.insert(w, at: 0); notify("Zur Wunschliste hinzugefügt") }
        catch { notify(errText(error), error: true) }
    }
    func removeWishlist(_ id: String) async {
        wishlist.removeAll { $0.id == id }; try? await api.deleteWishlist(id)
    }
    func moveWishlistToShelf(_ item: WishlistItem, shelfId: String) async {
        let r = BookSearchResult(title: item.title, authors: item.authors, publisher: item.publisher, publishedDate: item.publishedDate,
                                 description: item.description, pageCount: nil, categories: item.categories, thumbnail: item.thumbnail, isbn: item.isbn, source: item.source)
        if await addBook(r.toBook(bookshelfId: shelfId)) { await removeWishlist(item.id) }
    }

    // ── Helfer ──
    func reloadBooks() async { if let b = try? await api.fetchBooks() { books = b } }
    func reloadShelves() async { if let s = try? await api.fetchShelves() { shelves = s } }
    func notify(_ text: String, error: Bool = false) { message = text; messageIsError = error }
    private func errText(_ e: Error) -> String { (e as? APIError)?.errorDescription ?? "Fehler" }
}
