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
                .onOpenURL { app.handleDeepLink($0) }
        }
    }
}
