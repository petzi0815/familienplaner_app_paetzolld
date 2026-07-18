import SwiftUI
import UIKit

@MainActor
final class AppState: ObservableObject {
    enum MainTab: Hashable { case heute, bereiche, scan, inbox, smarthome }

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
    /// Angemeldete Person (für die persönliche Begrüßung auf „Heute").
    @Published var me: AuthMe?
    @Published var domains: [BereichDomain] = []
    @Published var resources: [ResourceInfo] = []
    /// Neuerer TestFlight-Build verfügbar (Buildnummer) → Update-Banner. nil = aktuell.
    @Published var updateBuild: Int?
    @Published var testflightURL: String?

    /// Status der Alarmo-Alarmanlage (Home Assistant). nil = noch nicht geladen.
    @Published var alarmo: AlarmoStatus?
    /// Läuft gerade ein Schaltvorgang (scharf/unscharf) → Steuerung sperren + Spinner.
    @Published var alarmoBusy = false
    /// Kurzlebige Fehlermeldung eines fehlgeschlagenen Schaltvorgangs (für den Toast in der Kachel).
    @Published var alarmoError: String?

    // ── Haus-Steuerung (Smart-Home-Tab): Raffstores + Szenen-Scripts ──
    @Published var houseConfigured = true
    @Published var houseCovers: [RaffstoreCover] = []
    @Published var houseScripts: [HouseScript] = []
    @Published var houseLoaded = false
    /// Kurzlebiger Toast der Haus-Steuerung.
    @Published var houseMessage: String?
    @Published var houseMessageIsError = false

    /// Kameras (über Home Assistant) für den Smart-Home-Tab.
    @Published var cameras: [Camera] = []
    @Published var camerasLoaded = false

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
        Task { await loadMe() }
        Task { await loadAlarmo() }
    }

    /// Alarmo-Status laden (unabhängig vom Dashboard, damit ein unerreichbares HA das Home nicht blockiert).
    func loadAlarmo() async {
        alarmo = try? await api.alarmoStatus()
    }

    /// Alarmo scharf/unscharf schalten. Der Server nutzt den hinterlegten PIN. Danach wird bis zum
    /// ENDZUSTAND beobachtet (Ausgangs-/Eingangsverzögerung kann bis ~1 Min dauern) — sonst bliebe die
    /// Kachel bei „Wird aktiviert …" hängen. Schlägt die Aktivierung fehl (z.B. offene Tür), Grund melden.
    func alarmoAction(_ action: String) async {
        let requestedArm = action != "disarm"
        alarmoBusy = true
        do {
            var status = try await api.alarmoAction(action)
            alarmo = status
            // Befehl ist abgesetzt → ab jetzt nur beobachten (kein Dauer-Spinner während der Verzögerung;
            // die Kachel zeigt „Wird aktiviert …" mit „Deaktivieren" zum Abbrechen).
            alarmoBusy = false
            var waited = 0.0
            while (status.isArming || status.state == "pending"), waited < 90 {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                waited += 2.5
                guard let s = try? await api.alarmoStatus() else { break }
                status = s
                alarmo = s
            }
            // Aktivierung angefordert, aber Panel ist (wieder) unscharf → fehlgeschlagen.
            if requestedArm && status.isDisarmed {
                if let open = status.openSensors, !open.isEmpty {
                    alarmoError = "Aktivierung fehlgeschlagen – offen: \(open.joined(separator: ", "))"
                } else {
                    alarmoError = "Aktivierung fehlgeschlagen (Sensor offen?)."
                }
            }
        } catch {
            alarmoBusy = false
            alarmoError = (error as? APIError)?.errorDescription ?? "Schalten fehlgeschlagen."
            await loadAlarmo()
        }
    }

    // ── Haus-Steuerung ──

    /// Kameraliste laden (Snapshots/Streams werden pro Kachel bei Bedarf geholt).
    func loadCameras() async {
        if let list = try? await api.cameras() { cameras = list.cameras }
        camerasLoaded = true
    }

    /// Raffstore-Zustände + Szenen-Scripts laden.
    func loadHouse() async {
        do {
            let d = try await api.houseState()
            houseConfigured = d.configured
            houseCovers = d.covers
            houseScripts = d.scripts
        } catch {
            houseMessage = (error as? APIError)?.errorDescription ?? "Haus-Steuerung nicht erreichbar."
            houseMessageIsError = true
        }
        houseLoaded = true
    }

    /// Ein Raffstore-Kommando senden; danach kurz nachladen (Cover fahren verzögert).
    func coverAction(entity: String, action: String, value: Int? = nil) async {
        do {
            let d = try await api.coverAction(entity: entity, action: action, value: value)
            houseCovers = d.covers
            houseScripts = d.scripts
            // Cover bewegen sich langsam → nach kurzer Zeit den echten Zustand nachziehen.
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if let fresh = try? await api.houseState() { houseCovers = fresh.covers }
        } catch {
            houseMessage = (error as? APIError)?.errorDescription ?? "Aktion fehlgeschlagen."
            houseMessageIsError = true
            await loadHouse()
        }
    }

    /// Ein Szenen-Script ausführen; danach nachladen.
    func runScript(_ script: HouseScript) async {
        do {
            try await api.runScript(entity: script.entity)
            houseMessage = "„\(script.name)“ ausgeführt."
            houseMessageIsError = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if let fresh = try? await api.houseState() { houseCovers = fresh.covers }
        } catch {
            houseMessage = (error as? APIError)?.errorDescription ?? "Script fehlgeschlagen."
            houseMessageIsError = true
        }
    }

    /// Angemeldete Identität laden (Rolle + Person) — für die Begrüßung.
    func loadMe() async { if let m = try? await api.authMe() { me = m } }

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

    /// Eine Aufgabe abhaken. Familien-Aufgaben laufen über die recurring-aware /complete-Route,
    /// Garten-Aufgaben über ein PATCH auf garten-aufgaben (erledigt=1). Danach Dashboard neu laden.
    func completeTask(_ task: TaskItem) async {
        guard let rid = task.refId else { return }
        do {
            if task.source == "garten" {
                try await api.patchRecord("garten-aufgaben", id: String(rid),
                                          fields: ["erledigt": 1, "erledigt_am": ISO8601DateFormatter().string(from: Date())])
            } else {
                try await api.completeAufgabe(id: rid)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await loadDashboard()
        } catch {
            aufgabenError = (error as? APIError)?.errorDescription ?? "Aufgabe konnte nicht aktualisiert werden."
        }
    }

    /// Aufgabe umschalten: offene abhaken, erledigte wieder öffnen (Undo bei Versehen).
    func toggleTask(_ task: TaskItem) async {
        if task.isDone { await reopenTask(task) } else { await completeTask(task) }
    }

    /// Eine erledigte Aufgabe wieder öffnen (versehentlich abgehakt). Familie → status='offen',
    /// Garten → erledigt=0. Danach Dashboard neu laden (verschiebt sie zurück in „Offen").
    func reopenTask(_ task: TaskItem) async {
        guard let rid = task.refId else { return }
        do {
            if task.source == "garten" {
                try await api.patchRecord("garten-aufgaben", id: String(rid), fields: ["erledigt": 0])
            } else {
                try await api.patchRecord("aufgaben", id: String(rid), fields: ["status": "offen"])
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await loadDashboard()
        } catch {
            aufgabenError = (error as? APIError)?.errorDescription ?? "Aufgabe konnte nicht wieder geöffnet werden."
        }
    }

    /// Neue Familien-Aufgabe anlegen (generisches CRUD). Gibt Erfolg zurück (Sheet schließt dann).
    func createAufgabe(_ fields: [String: Any]) async -> Bool {
        do {
            _ = try await api.createRecord("aufgaben", fields: fields)
            await loadDashboard()
            return true
        } catch {
            aufgabenError = (error as? APIError)?.errorDescription ?? "Aufgabe konnte nicht angelegt werden."
            return false
        }
    }

    /// Kurzlebige Fehlermeldung rund um Aufgaben (Toast auf „Heute").
    @Published var aufgabenError: String?

    /// APNs-Device-Token ans Backend melden (nur wenn angemeldet).
    func registerPushToken(_ token: String) async {
        guard settings.isConfigured else { return }
        try? await api.registerPush(token: token)
    }
}
