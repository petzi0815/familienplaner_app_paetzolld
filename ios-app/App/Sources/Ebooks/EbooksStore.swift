import SwiftUI

/// Zentraler Zustand der E-Book-Wunschliste (Items, Kategorien/Jahre, Filter, Stats, Mutationen).
/// Kategorien/Jahre hängen NICHT von den Filtern ab → einmal beim Laden holen und cachen
/// (statt dem Web-Original mit Dreifach-Fetch pro Filterwechsel).
@MainActor
final class EbooksStore: ObservableObject, NotifiableStore {
    let api: EbooksAPI

    @Published var items: [EbookItem] = []
    @Published var categories: [String] = []
    @Published var years: [String] = []

    @Published var filters = EbookFilters()
    @Published var tab: EbookTab = .wunschliste
    @Published var loading = true
    @Published var message: String?
    @Published var messageIsError = false

    // Externe Suche (Shelfmark)
    @Published var searchQuery = ""
    @Published var searchResults: [ShelfmarkResult] = []
    @Published var searching = false
    @Published var searchError: String?
    @Published var downloadingID: String?

    // Wunschlisten-Retry
    @Published var checkingID: Int?
    @Published var bulkChecking = false

    // Calibre-Bibliothek
    @Published var calibreBooks: [CalibreBook] = []
    @Published var calibreShelves: [CalibreShelf] = []
    @Published var calibreShelf: Int? = nil
    @Published var calibreSearch = ""
    @Published var calibreLoading = false
    @Published var calibreLoadingMore = false
    @Published var calibreTotal = 0
    @Published var calibreSort: CalibreSort = .neueste
    private var calibreSearchTask: Task<Void, Never>?

    init(settings: Settings) { api = EbooksAPI(settings: settings) }

    private static let ymd: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    static var todayYMD: String { ymd.string(from: Date()) }

    // MARK: - Laden

    func loadAll() async {
        loading = true
        async let itemsT = api.fetchItems(filters)
        async let catsT = api.fetchCategories()
        async let yearsT = api.fetchYears()
        items = (try? await itemsT) ?? []
        categories = (try? await catsT) ?? []
        years = (try? await yearsT) ?? []
        loading = false
    }

    func reloadItems() async {
        if let i = try? await api.fetchItems(filters) { items = i }
    }

    // MARK: - Filter

    func setStatus(_ s: String?) async {
        filters.status = (filters.status == s) ? nil : s
        await reloadItems()
    }
    func setYear(_ y: String?) async {
        filters.year = y
        await reloadItems()
    }
    func setCategory(_ cat: String?) async {
        filters.category = cat
        await reloadItems()
    }
    func applySearch() async { await reloadItems() }

    /// ✕ — nur Jahr/Kategorie/Suche zurücksetzen (Status bleibt).
    func clearFilters() async {
        filters.year = nil; filters.category = nil; filters.search = ""
        await reloadItems()
    }

    // MARK: - Abgeleitete Stats (filter-skopiert, aus den geladenen Items — wie das Original)

    var statGesamt: Int { items.count }
    var statGesucht: Int { items.filter { $0.status == "gesucht" }.count }
    var statGeladen: Int { items.filter { $0.status == "heruntergeladen" }.count }

    // MARK: - Mutationen

    /// Manuell zur Wunschliste hinzufügen (POST — funktioniert ohne externen Dienst).
    func createManual(title: String, author: String, publisher: String, year: String,
                      category: String, language: String, isbn: String,
                      descriptionText: String, notes: String) async -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { notify("Titel fehlt", error: true); return false }
        var body: [String: Any] = [
            "title": t,
            "language": language.isEmpty ? "de" : language,
            "status": "gesucht",
            "requested_by": "Manuell",
            "requested_at": Self.todayYMD,
        ]
        addIfPresent(&body, "author", author)
        addIfPresent(&body, "publisher", publisher)
        addIfPresent(&body, "year", year)
        addIfPresent(&body, "category", category)
        addIfPresent(&body, "isbn", isbn)
        addIfPresent(&body, "description", descriptionText)
        addIfPresent(&body, "notes", notes)
        do {
            _ = try await api.createItem(body)
            await reloadItems()
            await reloadOptions()
            notify("Auf die Wunschliste gesetzt")
            return true
        } catch { notify(errText(error), error: true); return false }
    }

    /// Bearbeiten speichern (Whitelist-Felder aus dem Detail-Formular).
    func saveItem(_ id: Int, fields: [String: Any]) async -> Bool {
        do {
            try await api.updateItem(id, fields)
            await reloadItems()
            await reloadOptions()
            notify("Gespeichert")
            return true
        } catch { notify(errText(error), error: true); return false }
    }

    /// Status umschalten (gesucht ↔ heruntergeladen). Setzt beim Markieren das Ladedatum.
    func toggleStatus(_ item: EbookItem) async -> Bool {
        let now = item.isDownloaded
        var fields: [String: Any] = ["status": now ? "gesucht" : "heruntergeladen"]
        if !now { fields["downloaded_at"] = Self.todayYMD }
        return await saveItem(item.id, fields: fields)
    }

    func deleteItem(_ item: EbookItem) async {
        items.removeAll { $0.id == item.id }
        do { try await api.deleteItem(item.id) }
        catch { await reloadItems(); notify(errText(error), error: true) }
    }

    // MARK: - Externe Suche (Shelfmark)

    /// Externe Buchsuche ausführen (min. 2 Zeichen).
    func performSearch() async {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { searchResults = []; searchError = nil; return }
        searching = true; searchError = nil
        do {
            let r = try await api.searchExternal(q)
            searchResults = r
            searchError = r.isEmpty ? "Keine Treffer." : nil
        } catch {
            searchResults = []
            searchError = errText(error)
        }
        searching = false
    }

    /// Treffer herunterladen (addOnly=false) oder nur auf die Wunschliste setzen (addOnly=true).
    func downloadResult(_ r: ShelfmarkResult, addOnly: Bool) async {
        downloadingID = r.id
        defer { downloadingID = nil }
        do {
            let res = try await api.download(r.raw, addOnly: addOnly)
            notify((res["message"] as? String) ?? (addOnly ? "Zur Wunschliste hinzugefügt" : "Download gestartet"))
            await reloadItems(); await reloadOptions()
        } catch { notify(errText(error), error: true) }
    }

    // MARK: - Wunschlisten-Retry (Shelfmark)

    /// Ein Buch prüfen + laden; Status/attempts aktualisieren.
    func checkBook(_ item: EbookItem) async {
        checkingID = item.id
        defer { checkingID = nil }
        do {
            let r = try await api.wishlistCheck(item.id)
            if Coerce.bool(r["downloaded"]) {
                notify("„\(item.title)“ heruntergeladen")
            } else {
                notify("„\(item.title)“: \((r["message"] as? String) ?? "kein Treffer")", error: true)
            }
            await reloadItems()
        } catch { notify(errText(error), error: true) }
    }

    /// Alle gesuchten Bücher im Hintergrund prüfen, danach neu laden.
    func checkAllWishlist() async {
        bulkChecking = true
        defer { bulkChecking = false }
        do {
            let pending = try await api.wishlistCheckAll()
            notify("Prüfe \(pending) Bücher im Hintergrund …")
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            await reloadItems(); await reloadOptions()
        } catch { notify(errText(error), error: true) }
    }

    /// Erfolgreich heruntergeladene Bücher aus der Wunschliste entfernen.
    func cleanupDownloaded() async {
        do {
            let n = try await api.wishlistCleanup()
            notify("\(n) fertige Bücher entfernt")
            await reloadItems(); await reloadOptions()
        } catch { notify(errText(error), error: true) }
    }

    // MARK: - Calibre-Bibliothek

    func loadCalibre() async {
        if calibreShelves.isEmpty { calibreShelves = (try? await api.calibreShelves()) ?? [] }
        await calibreReload()
    }

    func calibreReload() async {
        calibreLoading = true
        do {
            let r = try await api.calibreBooks(search: calibreSearch, shelf: calibreShelf, offset: 0,
                                               sort: calibreSort.sortParam, order: calibreSort.orderParam)
            calibreBooks = r.rows   // Hauptliste server-sortiert; Regal-Inhalt in nativer Reihenfolge.
            calibreTotal = r.total
        } catch { notify(errText(error), error: true) }
        calibreLoading = false
    }

    /// Weitere Seite (nur in der Gesamtliste, nicht im Regal-Filter).
    func calibreLoadMore() async {
        guard !calibreLoadingMore, calibreShelf == nil, calibreBooks.count < calibreTotal else { return }
        calibreLoadingMore = true
        if let r = try? await api.calibreBooks(search: calibreSearch, shelf: nil, offset: calibreBooks.count,
                                               sort: calibreSort.sortParam, order: calibreSort.orderParam) {
            let seen = Set(calibreBooks.map(\.id))
            calibreBooks.append(contentsOf: r.rows.filter { !seen.contains($0.id) })
        }
        calibreLoadingMore = false
    }

    func setCalibreSort(_ s: CalibreSort) async {
        calibreSort = s
        await calibreReload()
    }

    func setCalibreShelf(_ id: Int?) async {
        calibreShelf = (calibreShelf == id) ? nil : id
        await calibreReload()
    }

    func calibreSearchChanged() {
        calibreSearchTask?.cancel()
        calibreSearchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.calibreReload()
        }
    }

    func addToShelf(_ book: CalibreBook, shelf: CalibreShelf) async {
        do {
            _ = try await api.calibreShelfAction(bookId: book.id, shelfId: shelf.id, action: "add")
            notify("Auf Regal „\(shelf.name)“ gelegt")
        } catch { notify(errText(error), error: true) }
    }

    private func reloadOptions() async {
        if let c = try? await api.fetchCategories() { categories = c }
        if let y = try? await api.fetchYears() { years = y }
    }

    // MARK: - Helfer
    // notify(_:error:) und errText(_:) kommen aus NotifiableStore.

    private func addIfPresent(_ body: inout [String: Any], _ key: String, _ value: String) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !v.isEmpty { body[key] = v }
    }
}
