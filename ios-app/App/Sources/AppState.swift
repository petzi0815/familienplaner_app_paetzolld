import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum MainTab: Hashable { case heute, bereiche, scan, inbox, search }

    @Published var selectedTab: MainTab = .heute
    /// Hochzählen → der Erfassen-Tab öffnet die Kamera (aus Quick-Action/Siri).
    @Published var openCameraTick: Int = 0

    /// Kamera direkt öffnen (Home-Quick-Action „Foto aufnehmen" / Siri).
    func requestCamera() { selectedTab = .scan; openCameraTick += 1 }
    @Published var lebensbereiche: [Lebensbereich] = []
    @Published var inbox: [FotoInboxItem] = []
    @Published var inboxNeu: Int = 0
    @Published var dashboard: DashboardToday?
    @Published var dashboardError: String?
    @Published var domains: [BereichDomain] = []
    @Published var resources: [ResourceInfo] = []

    let settings: Settings
    let api: APIClient

    init(settings: Settings) {
        self.settings = settings
        self.api = APIClient(settings: settings)
    }

    func start() {
        Task { await loadLebensbereiche() }
        Task { await loadInbox() }
        Task { await loadDashboard() }
    }

    func loadLebensbereiche() async {
        if let list = try? await api.lebensbereiche() { lebensbereiche = list }
    }

    func loadInbox() async {
        if let list = try? await api.inbox() {
            inbox = list
            inboxNeu = list.filter { $0.status == "neu" }.count
        }
    }

    func loadCapabilities() async {
        guard domains.isEmpty else { return }
        if let caps = try? await api.capabilities() {
            resources = caps
            domains = DomainCatalog.build(from: caps)
        }
    }

    func loadDashboard() async {
        do {
            let d = try await api.dashboard()
            dashboard = d
            dashboardError = nil
            LocalReminders.reschedule(termine: d.termineUpcoming, vorrat: d.vorratBaldAblaufend, abfuhr: d.abfuhrNext ?? [])
        } catch {
            dashboardError = (error as? APIError)?.errorDescription ?? "Konnte Heute-Übersicht nicht laden."
        }
    }

    /// APNs-Device-Token ans Backend melden (nur wenn angemeldet).
    func registerPushToken(_ token: String) async {
        guard settings.isConfigured else { return }
        try? await api.registerPush(token: token)
    }
}
