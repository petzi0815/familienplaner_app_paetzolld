import SwiftUI

/// Zentraler Zustand des Familienkalenders (Liste + Monat, Kategorien, Filter, Suche, Mutationen).
@MainActor
final class TermineStore: ObservableObject, NotifiableStore {
    let api: TermineAPI

    // Daten
    @Published var termine: [Termin] = []          // Listenmodus (kategorie-gefiltert) — auch Basis der Stat-Pillen
    @Published var monthTermine: [Termin] = []      // Kalendermodus
    @Published var categories: [TerminCategory] = TermineStyle.defaultCategories

    // Steuerung
    @Published var mode: TermineMode = .liste
    @Published var selectedCategory: String? = nil
    @Published var showPast = false
    @Published var calYear: Int
    @Published var calMonth: Int                     // 1-basiert
    @Published var selectedDate: String? = nil

    // Suche
    @Published var search = ""
    @Published var searchResults: [Termin]? = nil
    @Published var searching = false
    private var searchTask: Task<Void, Never>?

    // Formular / Löschen / Status
    @Published var formRef: TermineFormRef?
    @Published var deleteTarget: Termin?

    @Published var loading = true
    @Published var message: String?
    @Published var messageIsError = false

    private var catByID: [String: TerminCategory] = [:]

    init(settings: Settings) {
        api = TermineAPI(settings: settings)
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        calYear = now.year ?? 2026
        calMonth = now.month ?? 1
        rebuildCategoryLookup()
    }

    // MARK: - Laden

    func loadAll() async {
        loading = true
        async let listT = api.fetchList(category: selectedCategory)
        async let catsT = api.fetchCategories()
        async let monthT = api.fetchMonth(year: calYear, month: calMonth)
        termine = (try? await listT) ?? []
        let cats = (try? await catsT) ?? []
        categories = cats.isEmpty ? TermineStyle.defaultCategories : cats
        monthTermine = (try? await monthT) ?? []
        rebuildCategoryLookup()
        loading = false
    }

    func reloadList() async {
        if let items = try? await api.fetchList(category: selectedCategory) { termine = items }
    }
    func reloadMonth() async {
        if let items = try? await api.fetchMonth(year: calYear, month: calMonth) { monthTermine = items }
    }

    private func rebuildCategoryLookup() {
        catByID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Filter / Monat / Tag

    func setCategory(_ id: String?) async {
        selectedCategory = (selectedCategory == id) ? nil : id
        await reloadList()
    }

    func prevMonth() {
        calMonth -= 1
        if calMonth < 1 { calMonth = 12; calYear -= 1 }
        selectedDate = nil
        Task { await reloadMonth() }
    }
    func nextMonth() {
        calMonth += 1
        if calMonth > 12 { calMonth = 1; calYear += 1 }
        selectedDate = nil
        Task { await reloadMonth() }
    }

    func selectDay(_ iso: String) { selectedDate = (selectedDate == iso) ? nil : iso }

    // MARK: - Suche (leichte Entprellung)

    var searchActive: Bool { search.trimmingCharacters(in: .whitespaces).count >= 2 }

    func searchChanged() {
        searchTask?.cancel()
        let q = search.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { searchResults = nil; searching = false; return }
        searching = true
        searchResults = nil
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            do {
                let r = try await self.api.search(q)
                if !Task.isCancelled { self.searchResults = r; self.searching = false }
            } catch {
                if !Task.isCancelled { self.searchResults = []; self.searching = false }
            }
        }
    }

    // MARK: - Abgeleitet (Kategorien / Sektionen / Stats)

    func category(_ id: String) -> TerminCategory {
        catByID[id]
            ?? TermineStyle.defaultCategories.first { $0.id == id }
            ?? TerminCategory(id: id, label: id, emoji: "📅", color: "blue")
    }

    private func sortAsc(_ a: Termin, _ b: Termin) -> Bool {
        if a.date != b.date { return a.date < b.date }
        return (a.time ?? "") < (b.time ?? "")
    }

    func isPast(_ t: Termin) -> Bool {
        (TermineDates.daysUntil(t.date) ?? 0) < 0 || t.status == "erledigt"
    }

    /// Offen & heute-oder-später.
    var upcomingItems: [Termin] {
        termine.filter { $0.status == "offen" && (TermineDates.daysUntil($0.date) ?? -999) >= 0 }.sorted(by: sortAsc)
    }
    /// Alle vergangenen/erledigten (für die Kopfzahl der Sektion).
    var allPastItems: [Termin] { termine.filter { isPast($0) } }
    /// Sichtbare vergangene: eingeklappt nur die letzten 7 Tage, aufgeklappt alle.
    var visiblePastItems: [Termin] {
        let items = showPast ? allPastItems : allPastItems.filter { (TermineDates.daysUntil($0.date) ?? -999) >= -7 }
        return items.sorted(by: sortAsc)
    }

    var statOffen: Int {
        termine.filter { $0.status == "offen" && (TermineDates.daysUntil($0.date) ?? -1) >= 0 }.count
    }
    var statThisWeek: Int {
        termine.filter {
            guard $0.status == "offen", let d = TermineDates.daysUntil($0.date) else { return false }
            return d >= 0 && d <= 7
        }.count
    }

    // MARK: - Kalender-Geometrie

    private func firstOfMonth() -> Date? {
        var c = DateComponents(); c.year = calYear; c.month = calMonth; c.day = 1
        return Calendar.current.date(from: c)
    }
    /// Führende Leerzellen bis zum 1. (Montag = Spalte 0).
    var leadingOffset: Int {
        guard let first = firstOfMonth() else { return 0 }
        let wd = Calendar.current.component(.weekday, from: first)   // 1=So … 7=Sa
        return (wd + 5) % 7
    }
    var daysInMonth: Int {
        guard let first = firstOfMonth(),
              let range = Calendar.current.range(of: .day, in: .month, for: first) else { return 30 }
        return range.count
    }
    func iso(day: Int) -> String { String(format: "%04d-%02d-%02d", calYear, calMonth, day) }

    /// Termine, die an `iso` liegen ODER als Mehrtages-Spanne darüber gehen.
    func eventsOn(_ iso: String) -> [Termin] {
        monthTermine.filter { t in
            if t.date == iso { return true }
            if let e = t.endDate, !e.isEmpty, t.date <= iso, iso <= e { return true }
            return false
        }.sorted(by: sortAsc)
    }
    func dotCount(_ iso: String) -> Int { min(eventsOn(iso).count, 3) }

    // MARK: - Mutationen

    func toggleStatus(_ t: Termin) async {
        let nv = t.isDone ? "offen" : "erledigt"
        do {
            try await api.update(t.id, ["status": nv])
            await reloadList(); await reloadMonth()
        } catch { notify(errText(error), error: true) }
    }

    func delete(_ t: Termin) async {
        do {
            try await api.delete(t.id)
            notify("Gelöscht")
            await reloadList(); await reloadMonth()
        } catch { notify(errText(error), error: true) }
    }

    /// Persönliches „gelesen"-Häkchen umschalten (nur eigener Zustand, ändert NICHT den geteilten Status).
    func toggleRead(_ t: Termin) async {
        do {
            try await api.setState(t.id, read: !t.read)
            await reloadList(); await reloadMonth()
        } catch { notify(errText(error), error: true) }
    }

    /// Persönliche Push-Benachrichtigung (2 & 1 Tag vorher) an/aus.
    func setNotify(_ t: Termin, _ on: Bool) async {
        do {
            try await api.setState(t.id, notify: on)
            notify(on ? "Benachrichtigung an (2 & 1 Tag vorher)" : "Benachrichtigung aus")
            await reloadList(); await reloadMonth()
        } catch { notify(errText(error), error: true) }
    }

    /// Anlegen (id == nil) oder Bearbeiten. Gibt Erfolg zurück (für Sheet-Dismiss).
    func saveTermin(id: Int?, body: [String: Any]) async -> Bool {
        do {
            if let id {
                try await api.update(id, body); notify("Gespeichert")
            } else {
                _ = try await api.create(body); notify("Termin angelegt")
            }
            await reloadList(); await reloadMonth()
            return true
        } catch { notify(errText(error), error: true); return false }
    }

    // notify(_:error:) und errText(_:) kommen aus NotifiableStore.
}
