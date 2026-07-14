import SwiftUI

/// Zentraler Zustand des Reiniger-Bereichs: Produkte, Anwendungen, Stats, Suche, Tab.
/// Alle drei Datensaetze werden gemeinsam geladen; Suche filtert Produkte + Anwendungen serverseitig.
@MainActor
final class ReinigerStore: ObservableObject, NotifiableStore {
    let api: ReinigerAPI

    @Published var items: [ReinigerProdukt] = []
    @Published var anwendungen: [ReinigerAnwendung] = []
    @Published var stats = ReinigerStats()

    @Published var tab: ReinigerTab = .inventar
    @Published var search = ""
    @Published var loading = true
    @Published var message: String?
    @Published var messageIsError = false

    /// Verhindert, dass der Such-Debounce beim ersten Erscheinen (leere Suche) doppelt laedt.
    private(set) var initialized = false

    init(settings: Settings) { api = ReinigerAPI(settings: settings) }

    // MARK: - Laden

    func loadAll() async {
        loading = true
        async let itemsT = api.fetchItems(search: search)
        async let statsT = api.fetchStats()
        async let anwT = api.fetchAnwendungen(search: search)
        items = (try? await itemsT) ?? []
        stats = (try? await statsT) ?? ReinigerStats()
        anwendungen = (try? await anwT) ?? []
        loading = false
        initialized = true
    }

    /// Neu laden nach Suche/Mutation (ohne Ladeindikator).
    func reload() async {
        async let itemsT = api.fetchItems(search: search)
        async let statsT = api.fetchStats()
        async let anwT = api.fetchAnwendungen(search: search)
        if let i = try? await itemsT { items = i }
        if let s = try? await statsT { stats = s }
        if let a = try? await anwT { anwendungen = a }
    }

    // MARK: - Abgeleitet

    /// Inventar: `entsorgt` ausgeblendet, nach Kategorie gruppiert (Server-Reihenfolge erhalten).
    var inventarGroups: [(kategorie: String, items: [ReinigerProdukt])] {
        var order: [String] = []
        var map: [String: [ReinigerProdukt]] = [:]
        for it in items where it.status != "entsorgt" {
            let k = it.kategorie ?? "spezial"
            if map[k] == nil { order.append(k) }
            map[k, default: []].append(it)
        }
        return order.map { (kategorie: $0, items: map[$0] ?? []) }
    }

    /// Einkaufsliste: restock-markiert UND Status leer/nachkaufen (clientseitig).
    var restockItems: [ReinigerProdukt] {
        items.filter { $0.restock && ($0.status == "leer" || $0.status == "nachkaufen") }
    }

    /// Oberflaechen-Optionen fuer den Ratgeber: `alle` + distinct sortiert.
    var surfaces: [String] {
        let set = Set(anwendungen.compactMap { $0.surface }.filter { !$0.isEmpty })
        let sorted = set.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return ["alle"] + sorted
    }

    /// Produkt-Info-Fallback im Ratgeber (Anker fuer Produkt-Links).
    var produktInfos: [ReinigerProdukt] {
        items.filter { ($0.flecken?.isEmpty == false) || ($0.pflegehinweise?.isEmpty == false) }
    }

    func linkedAnwendungen(_ id: Int) -> [ReinigerAnwendung] {
        anwendungen.filter { $0.reinigerID == id }
    }

    func product(id: Int?) -> ReinigerProdukt? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    // MARK: - Mutationen

    func setStatus(_ id: Int, _ status: String) async {
        do { try await api.updateProduct(id, ["status": status]); await reload() }
        catch { notify(errText(error), error: true) }
    }

    @discardableResult
    func saveProduct(id: Int?, fields: [String: Any]) async -> Bool {
        do {
            if let id { try await api.updateProduct(id, fields) }
            else { _ = try await api.createProduct(fields) }
            await reload()
            notify(id == nil ? "Hinzugefügt" : "Gespeichert")
            return true
        } catch { notify(errText(error), error: true); return false }
    }

    @discardableResult
    func deleteProduct(_ id: Int) async -> Bool {
        do { try await api.deleteProduct(id); await reload(); notify("Gelöscht"); return true }
        catch { notify(errText(error), error: true); return false }
    }

    // notify(_:error:) und errText(_:) kommen aus NotifiableStore.
}
