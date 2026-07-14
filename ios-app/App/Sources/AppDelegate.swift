import SwiftUI
import UIKit
import UserNotifications

/// Registriert das APNs-Device-Token und meldet es ans Backend (POST /api/v1/push/register).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static weak var appState: AppState?

    /// Erlaubte Ausrichtungen. Standard = nur Hochformat; die Live-Kamera erlaubt zusätzlich Querformat.
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
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
        Task { await AppDelegate.appState?.registerPushToken(hex) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Best-effort — ohne Push läuft die App normal weiter.
    }

    /// Home-Screen-Quick-Actions (Icon-Longpress) → passender Tab.
    func application(_ application: UIApplication,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let type = shortcutItem.type
        Task { @MainActor in
            if type.hasSuffix("newphoto") { AppDelegate.appState?.requestCamera() }
            else if type.hasSuffix("scanbook") { AppDelegate.appState?.selectedTab = .scan }
            else if type.hasSuffix("today") { AppDelegate.appState?.selectedTab = .heute }
        }
        completionHandler(true)
    }

    /// Notifications auch im Vordergrund als Banner/Ton zeigen.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}
