import SwiftUI

/// Zentraler Zustand des Samu-Inventars (Items, Marken, Bedarf, Stats, Matrix, Filter).
@MainActor
final class SamuStore: ObservableObject, NotifiableStore {
    let api: SamuAPI

    @Published var items: [SamuItem] = []
    @Published var marken: [SamuMarke] = []
    @Published var bedarf: [SamuBedarf] = []
    @Published var stats = SamuStats()
    @Published var matrix: [SamuMatrixCell] = []

    @Published var filters = SamuFilters()
    @Published var availableKategorien: [String] = []
    @Published var availableGroessen: [String] = []

    @Published var tab: SamuTab = .inventar
    @Published var loading = true
    @Published var message: String?
    @Published var messageIsError = false

    private var markenByName: [String: SamuMarke] = [:]

    init(settings: Settings) { api = SamuAPI(settings: settings) }

    // MARK: - Laden

    func loadAll() async {
        loading = true
        async let itemsT = api.fetchItems(filters)
        async let statsT = api.fetchStats()
        async let markenT = api.fetchMarken()
        async let matrixT = api.fetchMatrix()
        items = (try? await itemsT) ?? []
        stats = (try? await statsT) ?? SamuStats()
        marken = (try? await markenT) ?? []
        matrix = (try? await matrixT) ?? []
        markenByName = Dictionary(marken.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        await reloadDependentOptions()
        await reloadBedarf()
        loading = false
    }

    func reloadItems() async {
        if let i = try? await api.fetchItems(filters) { items = i }
    }
    func reloadStats() async {
        if let s = try? await api.fetchStats() { stats = s }
    }
    func reloadBedarf() async {
        if let b = try? await api.fetchBedarf() { bedarf = b }
    }
    private func reloadDependentOptions() async {
        availableKategorien = (try? await api.fetchKategorien(status: filters.status, typ: filters.typ)) ?? []
        availableGroessen = (try? await api.fetchGroessen(status: filters.status, typ: filters.typ)) ?? []
    }

    // MARK: - Filter-Setter (lösen die passenden Reloads aus)

    func setStatus(_ s: String?) async {
        filters.status = (filters.status == s) ? nil : s
        await reloadDependentOptions(); await reloadItems()
    }
    func setTyp(_ t: String?) async {
        let nv = (filters.typ == t) ? nil : t
        filters.typ = nv
        if nv == nil { filters.kategorie = nil }   // ohne Typ keine Kategorie-Pills
        await reloadDependentOptions(); await reloadItems()
    }
    func setKategorie(_ k: String?) async {
        filters.kategorie = (filters.kategorie == k) ? nil : k
        await reloadItems()
    }
    func setGroesse(_ g: String?) async {
        filters.groesse = g
        await reloadItems()
    }
    func setMarke(_ m: String?) {
        filters.marke = m   // rein clientseitig — kein Reload
    }
    func applySearch() async { await reloadItems() }

    func reset() async {
        filters = SamuFilters()
        await reloadDependentOptions(); await reloadItems()
    }

    /// Matrix-Zelle angetippt → Filter setzen und in den Inventar-Tab wechseln.
    func focusMatrix(kategorie: String, groesse: String) async {
        filters = SamuFilters(status: nil, typ: "kleidung", kategorie: kategorie, groesse: groesse, marke: nil, search: "")
        tab = .inventar
        await reloadDependentOptions(); await reloadItems()
    }

    // MARK: - Abgeleitet

    /// Server filtert bereits alles außer `marke` (clientseitig).
    var visibleItems: [SamuItem] {
        guard let m = filters.marke, !m.isEmpty else { return items }
        return items.filter { $0.marke == m }
    }
    /// Markennamen der aktuell geladenen Items (für das Marke-Dropdown).
    var availableMarken: [String] {
        Array(Set(items.compactMap { $0.marke }).filter { !$0.isEmpty }).sorted()
    }
    func marke(named name: String?) -> SamuMarke? {
        guard let name else { return nil }
        return markenByName[name]
    }

    var offeneBedarf: [SamuBedarf] { bedarf.filter { !$0.erledigt } }
    var erledigteBedarf: [SamuBedarf] { bedarf.filter { $0.erledigt } }

    // MARK: - Mutationen

    /// Status-Schnellumschaltung im Detail (nur aktiv ↔ eingelagert).
    func toggleStatus(_ item: SamuItem) async {
        let nv = item.status == "aktiv" ? "eingelagert" : "aktiv"
        do {
            try await api.updateItem(item.id, ["status": nv])
            await reloadItems(); await reloadStats()
        } catch { notify(errText(error), error: true) }
    }

    /// Bearbeiten speichern (nur Whitelist-Felder).
    func saveItem(_ id: Int, fields: [String: Any]) async -> Bool {
        do {
            try await api.updateItem(id, fields)
            await reloadItems(); await reloadStats()
            notify("Gespeichert")
            return true
        } catch { notify(errText(error), error: true); return false }
    }

    func addBedarf(beschreibung: String, kategorie: String, groesse: String, prioritaet: String, notizen: String) async -> Bool {
        do {
            _ = try await api.addBedarf(beschreibung: beschreibung, kategorie: kategorie, groesse: groesse, prioritaet: prioritaet, notizen: notizen)
            await reloadBedarf()
            notify("Hinzugefügt")
            return true
        } catch { notify(errText(error), error: true); return false }
    }

    func toggleBedarf(_ b: SamuBedarf) async {
        // optimistisch
        if let i = bedarf.firstIndex(where: { $0.id == b.id }) { bedarf[i].erledigt.toggle() }
        do { try await api.setBedarfErledigt(b.id, !b.erledigt); await reloadBedarf() }
        catch { await reloadBedarf(); notify(errText(error), error: true) }
    }

    func deleteBedarf(_ b: SamuBedarf) async {
        bedarf.removeAll { $0.id == b.id }
        do { try await api.deleteBedarf(b.id) } catch { await reloadBedarf() }
    }

    // notify(_:error:) und errText(_:) kommen aus NotifiableStore.
}

enum SamuTab: Hashable { case inventar, uebersicht, bedarf }
