import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum MainTab: Hashable { case heute, foto, inbox, scan, mehr, search }

    @Published var selectedTab: MainTab = .heute
    @Published var lebensbereiche: [Lebensbereich] = []
    @Published var inbox: [FotoInboxItem] = []
    @Published var inboxNeu: Int = 0
    @Published var dashboard: DashboardToday?
    @Published var dashboardError: String?

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

    func loadDashboard() async {
        do {
            let d = try await api.dashboard()
            dashboard = d
            dashboardError = nil
            LocalReminders.reschedule(termine: d.termineUpcoming, vorrat: d.vorratBaldAblaufend)
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
