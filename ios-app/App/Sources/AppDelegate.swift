import SwiftUI
import UIKit
import UserNotifications

/// Registriert das APNs-Device-Token und meldet es ans Backend (POST /api/v1/push/register).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static weak var appState: AppState?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
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
