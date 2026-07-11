import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum MainTab: Hashable { case camera, inbox, settings }

    @Published var selectedTab: MainTab = .camera
    @Published var lebensbereiche: [Lebensbereich] = []
    @Published var inbox: [FotoInboxItem] = []
    @Published var inboxNeu: Int = 0

    let settings: Settings
    let api: APIClient

    init(settings: Settings) {
        self.settings = settings
        self.api = APIClient(settings: settings)
    }

    func start() {
        Task { await loadLebensbereiche() }
        Task { await loadInbox() }
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

    /// APNs-Device-Token ans Backend melden (nur wenn angemeldet).
    func registerPushToken(_ token: String) async {
        guard settings.isConfigured else { return }
        try? await api.registerPush(token: token)
    }
}
