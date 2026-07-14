import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum MainTab: Hashable { case heute, bereiche, scan, inbox, search }

    @Published var selectedTab: MainTab = .heute
    /// Navigationspfad des Bereiche-Tabs (Deep-Link von den Home-KPI-Kacheln).
    @Published var bereichePath: [String] = []
    /// Hochzählen → der Erfassen-Tab öffnet die Kamera (aus Quick-Action/Siri).
    @Published var openCameraTick: Int = 0

    /// Kamera direkt öffnen (Home-Quick-Action „Foto aufnehmen" / Siri).
    func requestCamera() { selectedTab = .scan; openCameraTick += 1 }

    /// Einen Lebensbereich direkt öffnen (aus einer KPI-Kachel).
    func openBereich(_ key: String) { bereichePath = [key]; selectedTab = .bereiche }

    /// KPI-Kachel-Ziel auflösen: "inbox" | "heute" | "bereich:<key>".
    func openKpiTarget(_ target: String) {
        if target == "inbox" { selectedTab = .inbox }
        else if target == "heute" { selectedTab = .heute }
        else if target.hasPrefix("bereich:") { openBereich(String(target.dropFirst("bereich:".count))) }
    }
    @Published var lebensbereiche: [Lebensbereich] = []
    @Published var inbox: [FotoInboxItem] = []
    @Published var inboxNeu: Int = 0
    @Published var dashboard: DashboardToday?
    @Published var dashboardError: String?
    @Published var domains: [BereichDomain] = []
    @Published var resources: [ResourceInfo] = []
    /// Neuerer TestFlight-Build verfügbar (Buildnummer) → Update-Banner. nil = aktuell.
    @Published var updateBuild: Int?
    @Published var testflightURL: String?

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
        Task { await checkForUpdate() }
    }

    /// Prüft, ob im TestFlight ein neuerer Build als der installierte liegt.
    func checkForUpdate() async {
        guard let info = try? await api.appVersion(), let latest = info.latestBuild else { return }
        testflightURL = info.testflightUrl
        let current = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
        updateBuild = latest > current ? latest : nil
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
        // UI-Test ohne Backend: Bereiche-Grid statisch aus dem Katalog (Navigation offline testbar).
        if UITestMode.isActive {
            domains = DomainCatalog.buildStatic()
            return
        }
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
            // Termine laufen jetzt über den serverseitigen Per-User-Push (2 & 1 Tag vorher) →
            // lokal nur noch Vorrat (MHD) + Abfuhr planen (kein Doppel-Push).
            LocalReminders.reschedule(vorrat: d.vorratBaldAblaufend, abfuhr: d.abfuhrNext ?? [])
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
