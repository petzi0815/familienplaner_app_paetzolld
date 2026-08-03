import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

/// Registriert das APNs-Device-Token und meldet es ans Backend (POST /api/v1/push/register).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static weak var appState: AppState?

    /// Erlaubte Ausrichtungen. Standard = nur Hochformat; die Live-Kamera erlaubt zusätzlich Querformat.
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    /// Zuletzt registriertes APNs-Device-Token — beim Abmelden brauchen wir es, um die Zeile
    /// serverseitig zu löschen (sonst pusht der Server weiter an das abgemeldete Gerät).
    private static let deviceTokenKey = "apnsDeviceToken"

    /// Schnellaktion vom App-Icon, die noch keinen `appState` vorfand. Beim Kaltstart ist das der
    /// Normalfall: der Wunsch kommt in `configurationForConnecting` an, also lange bevor die erste
    /// View in `.onAppear` den `appState` setzt. Er wird deshalb hier geparkt und von
    /// `AppState.start()` eingelöst — sonst ginge er verloren und die App bliebe auf „Heute" stehen.
    /// Gleiches gilt, wenn beim Longpress niemand angemeldet war: dann löst der Login ihn ein.
    /// Wie `orientationLock` nur vom Main-Thread berührt.
    static var pendingShortcut: String?

    /// Deep-Link, der noch keinen empfangsbereiten `appState` vorfand — gleiche Mechanik wie
    /// `pendingShortcut`, nur für `familienplaner://…` (Widget, Live Activity, Push).
    /// Wird von `AppState.start()` eingelöst.
    static var pendingURL: URL?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        AppDelegate.registerNotificationCategories()
        // Nur noch Rückfalllinie: in einer SZENENBASIERTEN App (und der SwiftUI-App-Lifecycle ist
        // immer szenenbasiert) ist `launchOptions[.shortcutItem]` nicht verlässlich gefüllt — der
        // Kaltstart-Wunsch kommt in `configurationForConnecting` an. Bleibt als zweiter Weg stehen,
        // weil er nichts kostet und ohne Szenen-Konfiguration auskommt.
        if let item = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            AppDelegate.pendingShortcut = item.type
        }
        return true
    }

    /// **Der einzige Weg, auf dem eine Schnellaktion beim KALTSTART wirklich ankommt.**
    ///
    /// Vorher lauschte diese App auf `launchOptions[.shortcutItem]` und
    /// `application(_:performActionFor:)` — beides sind die Pfade der Zeit VOR den Szenen. Sobald
    /// eine App Szenen nutzt (SwiftUI-`WindowGroup` = Szene), ruft UIKit sie nicht mehr auf:
    /// der Kaltstart-Wunsch landet in `options.shortcutItem`, der Wunsch bei laufender App in
    /// `UIWindowSceneDelegate.windowScene(_:performActionFor:)`. Weil beide Handler nie feuerten,
    /// startete die App bei jedem Longpress einfach auf „Heute" (Fehlerbild von Lars).
    ///
    /// Die Szenen-Konfiguration wird hier NUR erzeugt, um den `SceneDelegate` einzuhängen — ohne
    /// Namen aus einem Szenen-Manifest (die Info.plist hat keins; mit `nil` legt UIKit eine
    /// Standardkonfiguration an). `SceneDelegate` implementiert bewusst KEIN
    /// `scene(_:willConnectTo:)`, damit er dem Fensteraufbau von SwiftUI nicht in die Quere kommt.
    ///
    /// **Achtung, teuer erkaufte Nebenwirkung:** sobald hier ein eigener `delegateClass` gesetzt wird,
    /// ist der szenenweite Delegate von SwiftUI (`SwiftUI.AppSceneDelegate`) NICHT mehr installiert.
    /// SwiftUI baut sein Fenster zwar weiterhin auf, bekommt aber die URL-Zustellung nicht mehr —
    /// `.onOpenURL` in `FamilienplanerApp` verstummt. Deshalb übernimmt dieser Delegate die
    /// Deep-Links selbst: Kaltstart über `options.urlContexts` (hier), laufende App über
    /// `SceneDelegate.scene(_:openURLContexts:)`. Ohne das wären alle `familienplaner://`-Links aus
    /// Widgets, Live Activity und Push tot — der Preis wäre höher als der behobene Fehler.
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem {
            AppDelegate.pendingShortcut = item.type
        }
        // Kaltstart per Deep-Link: dieselbe `ConnectionOptions`, die sonst `scene(_:willConnectTo:)`
        // bekäme. `min(by:)` statt `first`, weil ein Set keine feste Reihenfolge hat — praktisch
        // enthält es genau eine URL, aber die Auswahl soll nicht vom Zufall abhängen.
        if let url = options.urlContexts.map(\.url).min(by: { $0.absoluteString < $1.absoluteString }) {
            AppDelegate.pendingURL = url
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    /// Eine Schnellaktion ausführen — gemeinsamer Weg für Szenen-Delegate, den alten App-Delegate-Pfad
    /// und den Kaltstart. Ist die Oberfläche noch nicht empfangsbereit (App startet gerade, oder es ist
    /// niemand angemeldet), wird der Wunsch geparkt und von `AppState.start()` eingelöst.
    ///
    /// Bewusst OHNE Entprellung auf gleiche Typen: die drei `consume…`-Funktionen sind idempotent,
    /// ein doppeltes Anwenden ist also folgenlos — ein fälschlich verschluckter Wunsch dagegen genau
    /// der Fehler, den wir hier beheben.
    @MainActor
    static func handleShortcut(_ type: String) {
        if let state = AppDelegate.appState, state.settings.isConfigured {
            AppDelegate.pendingShortcut = nil
            state.applyShortcut(type)
        } else {
            AppDelegate.pendingShortcut = type
        }
    }

    /// Deep-Link (`familienplaner://…`) aus Widget, Live Activity oder Push ausführen.
    ///
    /// Ersetzt `.onOpenURL` — das schweigt, seit wir einen eigenen Szenen-Delegate einhängen
    /// (siehe `configurationForConnecting`). Gleiches Park-Verfahren wie bei den Schnellaktionen:
    /// solange die Tab-Ansicht nicht steht oder niemand angemeldet ist, wird der Wunsch geparkt und
    /// von `AppState.start()` eingelöst. `handleDeepLink` ist idempotent — falls SwiftUI den Link in
    /// irgendeiner Konstellation DOCH zustellt, ist die doppelte Anwendung folgenlos.
    @MainActor
    static func handleURL(_ url: URL) {
        if let state = AppDelegate.appState, state.settings.isConfigured {
            AppDelegate.pendingURL = nil
            state.handleDeepLink(url)
        } else {
            AppDelegate.pendingURL = url
        }
    }

    /// Aktions-Kategorie „TERMIN" — die drei Knöpfe direkt am Sperrbildschirm (ohne App-Start).
    /// Harter Vertrag mit dem Backend (`category: "TERMIN"`, Action-IDs `TERMIN_ACK|TERMIN_DONE|TERMIN_MUTE`).
    static func registerNotificationCategories() {
        // Ohne .foreground/.authenticationRequired → die Aktion läuft im Hintergrund,
        // die App wird nur kurz aufgeweckt (Background-Task-Klammer in didReceive).
        let ack = UNNotificationAction(identifier: "TERMIN_ACK", title: "Gelesen", options: [])
        let done = UNNotificationAction(identifier: "TERMIN_DONE", title: "Erledigt", options: [])
        let mute = UNNotificationAction(identifier: "TERMIN_MUTE", title: "Nicht mehr erinnern",
                                        options: [.destructive])
        let termin = UNNotificationCategory(identifier: "TERMIN",
                                            actions: [ack, done, mute],
                                            intentIdentifiers: [],
                                            options: [])
        UNUserNotificationCenter.current().setNotificationCategories([termin])
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }

    /// Erlaubte Ausrichtungen setzen und die aktuelle Ansicht neu bewerten lassen (dreht ggf. sofort zurück).
    @MainActor
    static func setOrientationLock(_ mask: UIInterfaceOrientationMask) {
        orientationLock = mask
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }

    /// Push-Berechtigung anfragen und (bei Erlaubnis) für Remote-Notifications registrieren.
    static func requestPushAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: AppDelegate.deviceTokenKey)
        Task { await AppDelegate.appState?.registerPushToken(hex) }
    }

    /// Beim Abmelden: Device-Token serverseitig entfernen (`DELETE /api/v1/push/register`).
    /// **Muss aufgerufen werden, SOLANGE der API-Key noch gesetzt ist** — der Request wird hier
    /// synchron gebaut und danach best-effort abgeschickt (blockiert den Logout nie).
    static func unregisterPushToken() {
        let defaults = UserDefaults.standard
        guard let token = defaults.string(forKey: deviceTokenKey), !token.isEmpty else { return }
        defaults.removeObject(forKey: deviceTokenKey)
        guard var req = SharedStore.request("/api/v1/push/register", method: "DELETE") else { return }
        req.timeoutInterval = 5
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token])
        Task.detached(priority: .utility) { _ = try? await URLSession.shared.data(for: req) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Best-effort — ohne Push läuft die App normal weiter.
    }

    /// Rückfalllinie für den Fall, dass die App doch einmal ohne Szenen läuft. In der aktuellen
    /// App ruft iOS stattdessen `SceneDelegate.windowScene(_:performActionFor:)` auf.
    func application(_ application: UIApplication,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let type = shortcutItem.type
        Task { @MainActor in AppDelegate.handleShortcut(type) }
        completionHandler(true)
    }

    /// Notifications auch im Vordergrund als Banner/Ton zeigen.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Reaktion auf eine Notification: Aktionsknopf → Quittieren per API (ohne App zu öffnen),
    /// Tippen auf das Banner → Deep-Link auf den Termin.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        // Das Backend spreadet `data` auf die oberste Ebene (`{aps, ...data}`) — der verschachtelte
        // Fall wird zusätzlich toleriert, falls die Payload einmal anders gebaut wird.
        let nested = info["data"] as? [AnyHashable: Any]
        let kind = (info["kind"] as? String) ?? (nested?["kind"] as? String)
        let rawId = info["id"] ?? nested?["id"]
        let terminId = (rawId as? Int) ?? Int((rawId as? String) ?? "")

        guard kind == "termin", let id = terminId else { completionHandler(); return }

        switch response.actionIdentifier {
        case "TERMIN_ACK", "TERMIN_DONE", "TERMIN_MUTE":
            let action: TerminAck.Action
            switch response.actionIdentifier {
            case "TERMIN_DONE": action = .erledigt
            case "TERMIN_MUTE": action = .stumm
            default: action = .gelesen
            }
            // Die Klammer MUSS synchron hier stehen — zwischen `Task {}` und `completionHandler()`
            // gibt es keinen Suspension-Point, der Task startet also erst nach der Rückkehr. Ohne
            // Klammer darf iOS den Prozess vorher suspendieren und der Ack-Request bricht ab.
            let bg = AppDelegate.beginAckBackgroundTask()
            Task { @MainActor in
                // Rückfallebene: falls der Task abgebrochen wird, schließt spätestens hier die
                // Klammer (`end()` ist idempotent, der Erfolgspfad beendet sie schon früher).
                defer { bg?.end() }
                // Bewusst OHNE AppState: für die Sperrbildschirm-Aktion startet iOS die App nur in
                // den Hintergrund — `appState` wird ausschließlich in `.onAppear` gesetzt und ist
                // dann nil. TerminAck/LiveActivityManager kommen ohne App-Zustand aus.
                await TerminAck.send(terminId: id, action: action)
                switch action {
                case .gelesen: await LiveActivityManager.shared.markAcked(terminId: id)
                case .erledigt, .stumm: await LiveActivityManager.shared.end(terminId: id)
                case .laut: break
                }
                WidgetCenter.shared.reloadAllTimelines()
                // Das Ack ist durch → Klammer schließen, bevor der rein optionale Teil läuft.
                bg?.end()
                // Nur falls die App ohnehin im Vordergrund läuft: sichtbaren Zustand nachziehen.
                // Im Hintergrund würde der Dashboard-Request die Hintergrundzeit nur verheizen.
                if UIApplication.shared.applicationState == .active {
                    await AppDelegate.appState?.loadDashboard()
                }
            }
        case UNNotificationDefaultActionIdentifier:
            Task { @MainActor in AppDelegate.appState?.openTermin(id: id) }
        default:
            break
        }
        completionHandler()
    }

    /// Hintergrund-Klammer für die Sperrbildschirm-Aktion öffnen — **nur** wenn wir wirklich auf
    /// dem Main-Thread laufen. Apple garantiert für `didReceive` keine Zustellung auf dem
    /// Main-Thread; `MainActor.assumeIsolated` wäre dort ein fatalError, aus einem Best-Effort-Ack
    /// würde also ein Absturz beim Antippen eines Mitteilungs-Knopfs. Ohne Klammer läuft das Ack
    /// trotzdem (nur ohne garantierte Hintergrundzeit).
    private static func beginAckBackgroundTask() -> AckBackgroundTask? {
        guard Thread.isMainThread else { return nil }
        return MainActor.assumeIsolated { AckBackgroundTask.start() }
    }
}

/// Hintergrund-Klammer als Referenztyp: der Ablauf-Handler und der Erfolgspfad müssen dieselbe
/// ID beenden können — eine eingefangene `var` dürfte der `Task`-Block nicht einmal lesen.
@MainActor
final class AckBackgroundTask {
    private var id: UIBackgroundTaskIdentifier = .invalid

    static func start() -> AckBackgroundTask {
        let task = AckBackgroundTask()
        task.begin()
        return task
    }

    /// Klammer öffnen. Der Ablauf-Handler schließt sie, falls iOS die Zeit vorher abläuft —
    /// ohne ihn beendet das System die App hart.
    private func begin() {
        id = UIApplication.shared.beginBackgroundTask(withName: "termin-ack") { [weak self] in
            self?.end()
        }
    }

    /// Idempotent — mehrfaches Beenden ist ein No-Op.
    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

/// Szenen-Delegate — zwei Aufgaben: **Schnellaktionen bei bereits laufender App** und **Deep-Links**.
///
/// Sobald eine App Szenen nutzt (der SwiftUI-App-Lifecycle tut das immer), stellt iOS den
/// Longpress-Wunsch hier zu und NICHT mehr über `UIApplicationDelegate.application(_:performActionFor:)`.
/// Der Kaltstart-Fall läuft über `AppDelegate.application(_:configurationForConnecting:options:)`.
///
/// Die URL-Zustellung ist KEINE Kür, sondern Pflicht: mit einem eigenen Szenen-Delegate ist der von
/// SwiftUI mitgebrachte nicht mehr installiert, `.onOpenURL` bekommt nichts mehr. Ohne
/// `scene(_:openURLContexts:)` wären damit alle `familienplaner://`-Links (Widgets, Live Activity,
/// Push) tot — die drei Deep-Link-XCUITests fielen sofort um.
///
/// Bewusst OHNE `scene(_:willConnectTo:)`: das Fenster baut weiterhin ausschließlich SwiftUI auf.
/// Wer hier ein eigenes Fenster erzeugt, hat einen schwarzen Bildschirm. Der Kaltstart-Anteil dieser
/// Methode (`connectionOptions`) ist ohnehin schon in `configurationForConnecting` abgedeckt — es ist
/// dasselbe `UIScene.ConnectionOptions`-Objekt.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let type = shortcutItem.type
        Task { @MainActor in AppDelegate.handleShortcut(type) }
        completionHandler(true)
    }

    /// Deep-Link bei laufender (auch nur im Hintergrund liegender) App — der Ersatz für `.onOpenURL`.
    /// Sortiert, weil ein Set keine feste Reihenfolge hat; praktisch enthält es genau eine URL.
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        let urls = URLContexts.map(\.url).sorted { $0.absoluteString < $1.absoluteString }
        Task { @MainActor in for url in urls { AppDelegate.handleURL(url) } }
    }
}
