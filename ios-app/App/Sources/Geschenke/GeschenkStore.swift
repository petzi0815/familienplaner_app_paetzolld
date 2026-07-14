import SwiftUI

/// Zentraler Zustand des Geschenkplaners (Dashboard, Kinder, Einkauf, Archiv, Toast).
/// Detailansichten (Ereignis, Kind) laden ihren eigenen lokalen Zustand ueber `store.api`.
@MainActor
final class GeschenkStore: ObservableObject, NotifiableStore {
    let api: GeschenkAPI

    @Published var tab: GeschenkTab = .uebersicht

    // Dashboard
    @Published var dashboard: GDashboard?
    @Published var loadingDashboard = false
    // Kinder
    @Published var kinder: [GKind] = []
    @Published var loadingKinder = false
    // Einkauf (ausgewaehlt + bestellt)
    @Published var einkauf: [GGeschenk] = []
    @Published var loadingEinkauf = false
    // Archiv
    @Published var archivKinder: [GKind] = []
    @Published var archivVergangene: [GVergangenes] = []
    @Published var loadingArchiv = false

    @Published var message: String?
    @Published var messageIsError = false

    init(settings: Settings) { api = GeschenkAPI(settings: settings) }

    // MARK: - Laden

    func loadDashboard() async {
        loadingDashboard = true
        dashboard = try? await api.dashboard()
        loadingDashboard = false
    }

    func loadKinder() async {
        loadingKinder = true
        kinder = (try? await api.kinder()) ?? []
        loadingKinder = false
    }

    func loadEinkauf() async {
        loadingEinkauf = true
        einkauf = (try? await api.geschenke(status: ["ausgewaehlt", "bestellt"])) ?? []
        loadingEinkauf = false
    }

    func loadArchiv() async {
        loadingArchiv = true
        async let k = api.kinder()
        async let v = api.vergangene(kindId: nil)
        archivKinder = (try? await k) ?? []
        archivVergangene = (try? await v) ?? []
        loadingArchiv = false
    }

    // MARK: - Mutationen (Tab-Ebene)

    func confirmProfil(_ kindId: Int) async {
        do { try await api.confirmProfil(kindId); notify("Profil bestätigt ✅"); await loadDashboard() }
        catch { notify(errText(error), error: true) }
    }

    func setGeschenkStatus(_ id: Int, _ status: String) async {
        do {
            try await api.updateGeschenk(id, ["status": status])
            notify("Status → \(GStyle.statusLabel(status))")
            await loadEinkauf()
        } catch { notify(errText(error), error: true) }
    }

    func deleteKind(_ k: GKind) async {
        do { try await api.deleteKind(k.id); notify("Kind gelöscht"); await loadKinder() }
        catch { notify(errText(error), error: true) }
    }

    func createKind(name: String, geburtsdatum: String, profil: String, negativliste: String) async -> Bool {
        var body: [String: Any] = ["name": name]
        body["geburtsdatum"] = geburtsdatum.isEmpty ? NSNull() : geburtsdatum
        body["profil"] = profil.isEmpty ? NSNull() : profil
        body["negativliste"] = negativliste.isEmpty ? NSNull() : negativliste
        do {
            _ = try await api.createKind(body)
            notify("Kind angelegt ✅")
            await loadKinder()
            return true
        } catch { notify(errText(error), error: true); return false }
    }

    /// Matrix speichern: fuer jedes Kind Anlaesse als PUT, dann Ereignisse generieren.
    func saveMatrix(_ configsByKind: [Int: [[String: Any]]]) async {
        do {
            for (kindId, configs) in configsByKind {
                _ = try await api.putAnlaesse(kindId, configs: configs)
            }
            try await api.generieren()
            notify("Matrix gespeichert ✅")
            await loadKinder()
        } catch { notify(errText(error), error: true) }
    }

    func createVergangenes(kindId: Int, titel: String, anlass: String, jahr: Int?, notizen: String) async -> Bool {
        var body: [String: Any] = ["kind_id": kindId, "titel": titel]
        body["anlass"] = anlass.isEmpty ? NSNull() : anlass
        body["jahr"] = jahr.map { $0 as Any } ?? NSNull()
        body["notizen"] = notizen.isEmpty ? NSNull() : notizen
        do {
            _ = try await api.createVergangenes(body)
            notify("Eingetragen ✅")
            await loadArchiv()
            return true
        } catch { notify(errText(error), error: true); return false }
    }

    func deleteVergangenes(_ id: Int) async {
        do { try await api.deleteVergangenes(id); notify("Gelöscht"); await loadArchiv() }
        catch { notify(errText(error), error: true) }
    }

    // notify(_:error:) und errText(_:) kommen aus NotifiableStore.
}

enum GeschenkTab: Hashable { case uebersicht, einkauf, kinder, archiv }
// Detail-Pushes laufen über closure-basierte NavigationLinks (zuverlässig im gepushten Bereich,
// wie in Reisen); value-basierte navigationDestination-Registrierung auf einer gepushten View ist
// in SwiftUI flaky (Symptom: erster Tap „verschluckt", Zurück zeigt erst das Detail).
