import SwiftUI
import UIKit

/// Zentraler Zustand der Vorratskammer (Items, Einkaufsliste, Ablaufend, Rezepte, Stats).
/// Nach jeder Mutation werden die vier zusammenhängenden Listen + Stats frisch geladen
/// (keine optimistische UI — genau wie die Original-Seite, aber ohne globalen Blocker).
@MainActor
final class VorratStore: ObservableObject, NotifiableStore {
    let api: VorratAPI

    @Published var items: [VorratItem] = []          // aktive Lebensmittel (server-gefiltert)
    @Published var einkauf: [VorratItem] = []        // Einkaufsliste
    @Published var ablaufend: [VorratItem] = []      // bald ablaufend (14 Tage)
    @Published var rezepte: [VorratRezept] = []
    @Published var stats = VorratStats()

    @Published var filters = VorratFilters()
    @Published var tab: VorratTab = .vorrat
    @Published var loading = true
    @Published var message: String?
    @Published var messageIsError = false

    init(settings: Settings) { api = VorratAPI(settings: settings) }

    // MARK: - Laden

    func loadAll() async {
        loading = true
        async let itemsT = api.fetchItems(status: "aktiv", search: filters.search)
        async let statsT = api.fetchStats()
        async let einkaufT = api.fetchEinkauf()
        async let ablaufendT = api.fetchAblaufend()
        async let rezepteT = api.fetchRezepte()
        items = (try? await itemsT) ?? []
        stats = (try? await statsT) ?? VorratStats()
        einkauf = (try? await einkaufT) ?? []
        ablaufend = (try? await ablaufendT) ?? []
        rezepte = (try? await rezepteT) ?? []
        loading = false
    }

    /// Nur die Suche wirkt auf die aktive Liste (debounced im View).
    func applySearch() async {
        if let i = try? await api.fetchItems(status: "aktiv", search: filters.search) { items = i }
    }

    /// Refresh der vier zusammenhängenden Sichten nach einer Mutation (Rezepte ändern sich nicht).
    private func refresh() async {
        async let itemsT = api.fetchItems(status: "aktiv", search: filters.search)
        async let statsT = api.fetchStats()
        async let einkaufT = api.fetchEinkauf()
        async let ablaufendT = api.fetchAblaufend()
        let newItems = (try? await itemsT) ?? items
        let newStats = (try? await statsT) ?? stats
        let newEinkauf = (try? await einkaufT) ?? einkauf
        let newAblaufend = (try? await ablaufendT) ?? ablaufend
        items = newItems; stats = newStats; einkauf = newEinkauf; ablaufend = newAblaufend
    }

    // MARK: - Abgeleitet

    /// Aktive Items in fester Reihenfolge nach Kategorie gruppiert (leere Sektionen entfallen).
    var groupedItems: [(kategorie: String, items: [VorratItem])] {
        VorratKat.order.compactMap { k in
            let its = items.filter { $0.kategorie == k }
            return its.isEmpty ? nil : (k, its)
        }
    }

    // MARK: - Mutationen

    func consume(_ item: VorratItem) async {
        do { try await api.update(item.id, ["status": "verbraucht"]); await refresh(); notify("Als verbraucht markiert") }
        catch { notify(errText(error), error: true) }
    }

    func delete(_ item: VorratItem) async {
        do { try await api.delete(item.id); await refresh(); notify("Gelöscht") }
        catch { notify(errText(error), error: true) }
    }

    /// „Wieder da!" — zurück in den Vorrat, `verbraucht_am` explizit auf NULL.
    func wiederDa(_ item: VorratItem) async {
        do { try await api.update(item.id, ["status": "aktiv", "verbraucht_am": NSNull()]); await refresh(); notify("Wieder im Vorrat") }
        catch { notify(errText(error), error: true) }
    }

    /// „Kein Restock" — bleibt verbraucht, verschwindet von der Einkaufsliste.
    func keinRestock(_ item: VorratItem) async {
        do { try await api.update(item.id, ["restock": 0]); await refresh(); notify("Von der Einkaufsliste entfernt") }
        catch { notify(errText(error), error: true) }
    }

    @discardableResult
    func createItem(_ fields: [String: Any]) async -> Bool {
        do { _ = try await api.create(fields); await refresh(); notify("Hinzugefügt"); return true }
        catch { notify(errText(error), error: true); return false }
    }

    @discardableResult
    func updateItem(_ id: Int, _ fields: [String: Any]) async -> Bool {
        do { try await api.update(id, fields); await refresh(); notify("Gespeichert"); return true }
        catch { notify(errText(error), error: true); return false }
    }

    /// Foto hochladen → storage_key (für `bild_pfad`). nil bei Fehler (Save läuft dann ohne Bild weiter).
    func uploadPhoto(_ image: UIImage) async -> String? {
        guard let jpeg = image.jpegForUpload() else { return nil }
        return try? await api.uploadPhoto(jpeg: jpeg)
    }

    // notify(_:error:) und errText(_:) kommen aus NotifiableStore.
}
