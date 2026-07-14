import SwiftUI

/// Zentraler Zustand der Wunschliste (Events, Items, Auswahl, Filter, Mutationen).
@MainActor
final class WunschlisteStore: ObservableObject, NotifiableStore {
    let api: WunschlisteAPI

    @Published var events: [WunschEvent] = []
    @Published var items: [WunschItem] = []          // event-bezogen geladen (Alle = alle Events)

    @Published var selectedEventID: Int?             // nil = „🎁 Alle"
    @Published var statusFilter: String?             // clientseitig (offen/gekauft/geschenkt)
    @Published var search: String = ""

    @Published var loading = true
    @Published var message: String?
    @Published var messageIsError = false

    init(settings: Settings) { api = WunschlisteAPI(settings: settings) }

    // MARK: - Laden

    func loadAll() async {
        loading = true
        async let eventsT = api.fetchEvents()
        async let itemsT = api.fetchItems(eventId: selectedEventID)
        events = (try? await eventsT) ?? []
        items = (try? await itemsT) ?? []
        loading = false
    }

    /// Nur Items neu laden (nach Auswahlwechsel / Mutation).
    func reloadItems() async {
        if let i = try? await api.fetchItems(eventId: selectedEventID) { items = i }
    }
    /// Events neu laden (Zähler/Countdowns aktualisieren).
    func reloadEvents() async {
        if let e = try? await api.fetchEvents() { events = e }
    }

    // MARK: - Auswahl / Filter

    func selectEvent(_ id: Int?) async {
        guard selectedEventID != id else { return }
        selectedEventID = id
        await reloadItems()
    }

    func toggleStatusFilter(_ s: String) {
        statusFilter = (statusFilter == s) ? nil : s
    }

    // MARK: - Abgeleitet

    var selectedEvent: WunschEvent? {
        guard let id = selectedEventID else { return nil }
        return events.first { $0.id == id }
    }

    /// Kennzahlen aus den aktuell geladenen (event-bezogenen) Items — wie das Original.
    var stats: WunschStats { WunschStats(items: items) }

    /// Items nach Status-Filter + Suche (clientseitig).
    var visibleItems: [WunschItem] {
        var list = items
        if let s = statusFilter { list = list.filter { $0.status == s } }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter { it in
                [it.title, it.description, it.category, it.ean, it.price, it.purchasedBy]
                    .compactMap { $0?.lowercased() }
                    .contains { $0.contains(q) }
            }
        }
        return list
    }

    /// Nach Event gruppierte Items (für den „Alle"-Modus) — Reihenfolge = API-Reihenfolge.
    var groupedItems: [WunschGroup] {
        var order: [Int] = []
        var buckets: [Int: [WunschItem]] = [:]
        for it in visibleItems {
            if buckets[it.eventId] == nil { order.append(it.eventId) }
            buckets[it.eventId, default: []].append(it)
        }
        return order.map { eid in
            let ev = events.first { $0.id == eid }
            let sample = buckets[eid]?.first
            return WunschGroup(
                id: eid,
                name: ev?.name ?? sample?.eventName ?? "Anlass",
                emoji: ev?.emoji ?? sample?.eventEmoji ?? "🎁",
                event: ev,
                items: buckets[eid] ?? []
            )
        }
    }

    /// Items mit Link aber ohne Bild (für die deaktivierte „Anreichern"-Aktion).
    var enrichableCount: Int { items.filter { $0.imageURL == nil && $0.hasURL }.count }

    // MARK: - Mutationen (Items)

    /// Neues Geschenk. `event_id` wird immer mitgesendet (auch aus dem „Alle"-Modus via Picker).
    func addItem(eventId: Int, title: String, description: String, price: String,
                 url: String, category: String, ean: String, notes: String) async -> Bool {
        let fields: [String: Any] = [
            "event_id": eventId,
            "title": title,
            "description": optOrNull(description),
            "price": optOrNull(price),
            "url": optOrNull(url),
            "category": optOrNull(category),
            "ean": optOrNull(ean),
            "notes": optOrNull(notes),
        ]
        do {
            _ = try await api.addItem(fields)
            await reloadEvents(); await reloadItems()
            notify("Geschenk hinzugefügt 🎁")
            return true
        } catch { notify(errText(error), error: true); return false }
    }

    func saveItem(_ id: Int, title: String, description: String, price: String,
                  category: String, url: String, ean: String, notes: String) async -> Bool {
        let fields: [String: Any] = [
            "title": title,
            "description": optOrNull(description),
            "price": optOrNull(price),
            "category": optOrNull(category),
            "url": optOrNull(url),
            "ean": optOrNull(ean),
            "notes": optOrNull(notes),
        ]
        do {
            try await api.updateItem(id, fields)
            await reloadItems()
            notify("Gespeichert ✅")
            return true
        } catch { notify(errText(error), error: true); return false }
    }

    /// Status-Zyklus offen → gekauft → geschenkt → offen (optimistisch).
    func cycleStatus(_ item: WunschItem) async {
        let next = WunschStyle.nextStatus(item.status)
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].status = next }
        do {
            try await api.updateItem(item.id, ["status": next])
            await reloadEvents()
        } catch { await reloadItems(); notify(errText(error), error: true) }
    }

    func deleteItem(_ item: WunschItem) async {
        items.removeAll { $0.id == item.id }
        do {
            try await api.deleteItem(item.id)
            await reloadEvents()
        } catch { await reloadItems(); notify(errText(error), error: true) }
    }

    // MARK: - Mutationen (Events)

    func addEvent(name: String, emoji: String, date: String?) async -> Bool {
        do {
            let id = try await api.addEvent(name: name, emoji: emoji, date: date)
            await reloadEvents()
            selectedEventID = id > 0 ? id : selectedEventID
            await reloadItems()
            notify("Event angelegt 🎉")
            return true
        } catch { notify(errText(error), error: true); return false }
    }

    func deleteEvent(_ event: WunschEvent) async {
        do {
            try await api.deleteEvent(event.id)
            if selectedEventID == event.id { selectedEventID = nil }
            await reloadEvents(); await reloadItems()
            notify("Event gelöscht")
        } catch { notify(errText(error), error: true) }
    }

    func toggleReminders(_ event: WunschEvent) async {
        let nv = event.erinnerungenAktiv ? 0 : 1
        if let i = events.firstIndex(where: { $0.id == event.id }) { events[i].erinnerungenAktiv = (nv == 1) }
        do { try await api.updateEvent(event.id, ["erinnerungen_aktiv": nv]) }
        catch { await reloadEvents(); notify(errText(error), error: true) }
    }

    // MARK: - Helfer
    // notify(_:error:) und errText(_:) kommen aus NotifiableStore.

    /// Leerer Text → NSNull (Server-Konvention „leer = null").
    private func optOrNull(_ s: String) -> Any {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? NSNull() : t
    }
}

/// Eine nach Event gruppierte Item-Sektion (für den „Alle"-Modus).
struct WunschGroup: Identifiable {
    let id: Int
    let name: String
    let emoji: String
    let event: WunschEvent?
    let items: [WunschItem]
}
