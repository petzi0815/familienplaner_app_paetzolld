import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settings: Settings

    var body: some View {
        Group {
            if settings.isConfigured {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.default, value: settings.isConfigured)
    }
}

struct MainTabView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        TabView(selection: $app.selectedTab) {
            CameraView()
                .tabItem { Label("Foto", systemImage: "camera.fill") }
                .tag(AppState.MainTab.camera)

            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray.full.fill") }
                .badge(app.inboxNeu)
                .tag(AppState.MainTab.inbox)

            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape.fill") }
                .tag(AppState.MainTab.settings)
        }
        .task { app.start() }
    }
}
