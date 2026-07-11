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

/// iOS-26-Tab-Bar mit Liquid Glass: minimiert beim Scrollen, eigene Such-Rolle (schwebender Button).
struct MainTabView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        TabView(selection: $app.selectedTab) {
            Tab("Heute", systemImage: "house.fill", value: AppState.MainTab.heute) {
                HeuteView()
            }
            Tab("Bereiche", systemImage: "square.grid.2x2.fill", value: AppState.MainTab.bereiche) {
                BereicheHubView()
            }
            Tab("Erfassen", systemImage: "camera.viewfinder", value: AppState.MainTab.scan) {
                ScanHubView()
            }
            Tab("Inbox", systemImage: "tray.full.fill", value: AppState.MainTab.inbox) {
                InboxView()
            }
            .badge(app.inboxNeu)

            Tab("Suchen", systemImage: "magnifyingglass", value: AppState.MainTab.search, role: .search) {
                SearchView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .task {
            app.start()
            AppDelegate.requestPushAuthorization()
        }
    }
}
