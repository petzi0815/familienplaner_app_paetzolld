import SwiftUI

@main
struct FamilienplanerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: Settings
    @StateObject private var app: AppState

    init() {
        let s = Settings()
        _settings = StateObject(wrappedValue: s)
        _app = StateObject(wrappedValue: AppState(settings: s))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(settings)
                .tint(Theme.accent)
                .onAppear { AppDelegate.appState = app }
                // Deep-Links aus Widgets, Live Activity und Push (familienplaner://…).
                // Nur noch ZWEITER Weg: seit die App einen eigenen Szenen-Delegate einhängt
                // (AppDelegate.configurationForConnecting), ist der von SwiftUI mitgebrachte
                // Delegate nicht mehr installiert und `.onOpenURL` bekommt in der Regel nichts
                // mehr — die URLs kommen über SceneDelegate.scene(_:openURLContexts:) herein.
                // Bleibt trotzdem stehen: sollte UIKit die Szenen-Konfiguration einmal NICHT neu
                // bewerten (persistierte UISceneSession nach einem Update), ist der SwiftUI-Delegate
                // weiter aktiv und dies der einzige funktionierende Pfad. handleDeepLink ist
                // idempotent, doppelte Zustellung schadet also nicht.
                .onOpenURL { app.handleDeepLink($0) }
        }
    }
}
