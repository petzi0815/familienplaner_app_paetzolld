import SwiftUI

@main
struct FamilienplanerApp: App {
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
        }
    }
}
