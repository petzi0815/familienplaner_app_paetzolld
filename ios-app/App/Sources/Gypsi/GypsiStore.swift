import SwiftUI

/// Zentraler Zustand des Gypsi-Futters (volle Liste + clientseitige Filter/Stats/Optionen).
/// Native UX: die Liste wird EINmal geladen, Filter wirken sofort (kein Refetch pro Filterklick).
@MainActor
final class GypsiStore: ObservableObject {
    let api: GypsiAPI

    @Published var all: [GypsiFutter] = []              // serverseitig `erfasst_am DESC`
    @Published var statusFilter: GypsiStatusFilter = .alle
    @Published var markeFilter: String?
    @Published var geschmackFilter: String?
    @Published var search = ""

    @Published var loading = true
    @Published var busyIDs: Set<Int> = []               // laufende Toggle/Delete-Requests
    @Published var message: String?
    @Published var messageIsError = false

    init(settings: Settings) { api = GypsiAPI(settings: settings) }

    // MARK: - Laden

    func loadAll() async {
        loading = true
        all = (try? await api.fetchAll()) ?? []
        loading = false
    }
    func reload() async {
        if let f = try? await api.fetchAll() { all = f }
    }

    // MARK: - Abgeleitet

    /// Sichtbare Liste (Status + Marke + Geschmack + Volltextsuche). Reihenfolge bleibt DESC.
    var visible: [GypsiFutter] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { f in
            if statusFilter != .alle && f.status != statusFilter.rawValue { return false }
            if let m = markeFilter, f.marke != m { return false }
            if let g = geschmackFilter, (f.geschmack ?? "") != g { return false }
            if !q.isEmpty {
                let hay = [f.marke, f.sorte, f.geschmack ?? "", f.notizen ?? ""].joined(separator: " ")
                if !hay.localizedCaseInsensitiveContains(q) { return false }
            }
            return true
        }
    }

    // Stats aus der VOLLEN Liste (globale Zahlen — bewusst nicht der PWA-Quirk der gefilterten Zählung).
    var likedCount: Int { all.filter { $0.liked }.count }
    var dislikedCount: Int { all.filter { !$0.liked }.count }
    var total: Int { all.count }

    var availableMarken: [String] {
        Array(Set(all.map { $0.marke }).filter { !$0.isEmpty }).sorted()
    }
    var availableGeschmack: [String] {
        Array(Set(all.compactMap { $0.geschmack }).filter { !$0.isEmpty }).sorted()
    }
    /// Nur Marke/Geschmack (die „Filter löschen"-Aktion lässt den Status unberührt — wie in der PWA).
    var filtersActive: Bool { markeFilter != nil || geschmackFilter != nil }

    func clearFilters() { markeFilter = nil; geschmackFilter = nil }

    // MARK: - Mutationen

    func add(marke: String, sorte: String, geschmack: String, notizen: String) async -> Bool {
        do {
            _ = try await api.add(marke: marke, sorte: sorte,
                                  geschmack: geschmack.isEmpty ? nil : geschmack,
                                  notizen: notizen.isEmpty ? nil : notizen)
            await reload()
            notify("Futter hinzugefügt")
            return true
        } catch { notify(errText(error), error: true); return false }
    }

    func toggle(_ f: GypsiFutter) async {
        guard !busyIDs.contains(f.id) else { return }
        busyIDs.insert(f.id)
        let nv = f.liked ? "mag_er_nicht_mehr" : "mag_er"
        do { try await api.setStatus(f.id, nv); await reload() }
        catch { notify(errText(error), error: true) }
        busyIDs.remove(f.id)
    }

    func delete(_ f: GypsiFutter) async {
        guard !busyIDs.contains(f.id) else { return }
        busyIDs.insert(f.id)
        do {
            try await api.delete(f.id)
            all.removeAll { $0.id == f.id }
            notify("Gelöscht")
        } catch { notify(errText(error), error: true) }
        busyIDs.remove(f.id)
    }

    // MARK: - Helfer

    func notify(_ text: String, error: Bool = false) { message = text; messageIsError = error }
    private func errText(_ e: Error) -> String { (e as? APIError)?.errorDescription ?? "Fehler" }
}
