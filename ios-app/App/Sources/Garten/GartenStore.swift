import SwiftUI

/// Zentraler Zustand des Garten-Bereichs (Pflanzen, Samen, Aufgaben, Dünger, Stats, GTS, Filter).
@MainActor
final class GartenStore: ObservableObject, NotifiableStore {
    let api: GartenAPI

    @Published var tab: GartenTab = .pflanzen
    @Published var loading = true

    @Published var stats: GartenStats?
    @Published var gts: GTSResult?
    @Published var showGTS = false

    @Published var pflanzen: [GartenPflanze] = []
    @Published var pflanzenFilter = GartenPflanzenFilter()
    @Published var arten: [String] = []

    @Published var samen: [GartenSamen] = []
    @Published var samenFilter = GartenSamenFilter()

    @Published var aufgaben: [GartenAufgabe] = []
    @Published var aufgabenFilter = GartenAufgabenFilter()

    @Published var duenger: [GartenDuenger] = []
    @Published var duengerFilter = GartenDuengerFilter()

    @Published var message: String?
    @Published var messageIsError = false

    init(settings: Settings) { api = GartenAPI(settings: settings) }

    // MARK: - Laden

    func load() async {
        loading = true
        async let s = api.fetchStats()
        async let ar = api.fetchArten()
        async let g = api.fetchGts()
        stats = try? await s
        arten = (try? await ar) ?? []
        gts = try? await g
        await reloadPflanzen()
        loading = false
    }

    func reloadPflanzen() async { if let x = try? await api.fetchPflanzen(pflanzenFilter) { pflanzen = x } }
    func reloadSamen() async { if let x = try? await api.fetchSamen(samenFilter) { samen = x } }
    func reloadAufgaben() async { if let x = try? await api.fetchAufgaben(aufgabenFilter) { aufgaben = x } }
    func reloadDuenger() async { if let x = try? await api.fetchDuenger(duengerFilter) { duenger = x } }
    func reloadStats() async { if let x = try? await api.fetchStats() { stats = x } }

    // MARK: - Abgeleitet

    /// Clientseitig ermittelte Hersteller-Auswahl (aus den geladenen Samen).
    var herstellerOptions: [String] {
        Array(Set(samen.compactMap { $0.hersteller }).filter { !$0.isEmpty }).sorted()
    }
    /// Clientseitig ermittelte Typ-Auswahl (aus den geladenen Samen).
    var samenTypOptions: [String] {
        Array(Set(samen.compactMap { $0.typ }).filter { !$0.isEmpty }).sorted()
    }

    var aktiveSamen: [GartenSamen] { samen.filter { $0.aktiv } }
    var samenAufgaben: [GartenAufgabe] { aufgaben.filter { $0.samenId != nil } }

    // MARK: - Mutationen

    func addSamen(name: String) async -> Bool {
        let nummer = String(format: "%03d", samen.count + 1)
        do {
            _ = try await api.addSamen(nummer: nummer, name: name)
            await reloadSamen()
            notify("✨ Samen angelegt! Ole reichert die Daten automatisch an.")
            return true
        } catch { notify(errText(error), error: true); return false }
    }

    func toggleSamenAktiv(_ s: GartenSamen) async {
        do { try await api.setSamenAktiv(s.id, !s.aktiv); await reloadSamen() }
        catch { notify(errText(error), error: true) }
    }

    func deleteSamen(_ id: Int) async {
        do { try await api.deleteSamen(id); await reloadSamen(); await reloadStats() }
        catch { notify(errText(error), error: true) }
    }

    func addDuenger(name: String) async -> Bool {
        do {
            _ = try await api.addDuenger(name: name)
            await reloadDuenger(); await reloadStats()
            notify("✅ Dünger angelegt!")
            return true
        } catch { notify(errText(error), error: true); return false }
    }

    func setDuengerVorraetig(_ id: Int, to value: Bool) async {
        do { try await api.setDuengerVorraetig(id, value); await reloadDuenger() }
        catch { notify(errText(error), error: true) }
    }

    func deleteDuenger(_ id: Int) async {
        do { try await api.deleteDuenger(id); await reloadDuenger(); await reloadStats() }
        catch { notify(errText(error), error: true) }
    }

    func toggleAufgabe(_ a: GartenAufgabe) async {
        do { try await api.setAufgabeErledigt(a.id, !a.erledigt); await reloadAufgaben(); await reloadStats() }
        catch { notify(errText(error), error: true) }
    }

    func shiftAufgabe(_ a: GartenAufgabe, delta: Int) async {
        let current = a.computedMonat
        let nv = max(1, min(12, current + delta))
        if nv == current { return }
        do { try await api.setAufgabeMonat(a.id, nv); await reloadAufgaben() }
        catch { notify(errText(error), error: true) }
    }

    // notify(_:error:) und errText(_:) kommen aus NotifiableStore.
}
