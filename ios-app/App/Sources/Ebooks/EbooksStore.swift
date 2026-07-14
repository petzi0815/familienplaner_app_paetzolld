import SwiftUI

/// Zentraler Zustand der E-Book-Wunschliste (Items, Kategorien/Jahre, Filter, Stats, Mutationen).
/// Kategorien/Jahre hängen NICHT von den Filtern ab → einmal beim Laden holen und cachen
/// (statt dem Web-Original mit Dreifach-Fetch pro Filterwechsel).
@MainActor
final class EbooksStore: ObservableObject {
    let api: EbooksAPI

    @Published var items: [EbookItem] = []
    @Published var categories: [String] = []
    @Published var years: [String] = []

    @Published var filters = EbookFilters()
    @Published var tab: EbookTab = .wunschliste
    @Published var loading = true
    @Published var message: String?
    @Published var messageIsError = false

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

    private func reloadOptions() async {
        if let c = try? await api.fetchCategories() { categories = c }
        if let y = try? await api.fetchYears() { years = y }
    }

    // MARK: - Helfer

    func notify(_ text: String, error: Bool = false) { message = text; messageIsError = error }
    private func errText(_ e: Error) -> String { (e as? APIError)?.errorDescription ?? "Fehler" }
    private func addIfPresent(_ body: inout [String: Any], _ key: String, _ value: String) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !v.isEmpty { body[key] = v }
    }
}
