import SwiftUI
import UIKit

/// Einstellungen (Server/Konto/Version) — als Sheet aus dem Bereiche-Tab.
struct SettingsSheet: View {
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var me: AuthMe?
    @State private var feed: FeedSubscribeInfo?

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    LabeledContent("URL", value: settings.baseURL)
                }
                Section {
                    if let feed {
                        Button {
                            if let url = URL(string: feed.webcal) { UIApplication.shared.open(url) }
                        } label: { Label("Kalender abonnieren", systemImage: "calendar.badge.plus") }
                        Button {
                            UIPasteboard.general.string = feed.url
                        } label: { Label("Abo-Link kopieren", systemImage: "doc.on.doc") }
                    } else {
                        Text("Lädt …").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Kalender-Abo")
                } footer: {
                    Text("Termine, Abfuhr und Reisen als Kalender abonnieren — Änderungen erscheinen automatisch im lokalen Kalender.")
                }
                Section("Konto") {
                    if let me, me.authenticated {
                        LabeledContent("Angemeldet als", value: me.displayName)
                        if let role = me.role { LabeledContent("Rolle", value: role) }
                    }
                    Button(role: .destructive) {
                        settings.logout()
                        dismiss()
                    } label: {
                        Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
                Section {
                    LabeledContent("Version", value: "1.0")
                } footer: {
                    Text("Familienplaner – Fotos, Termine, Bücher, Vorräte und mehr. Der Agent Ole analysiert Uploads und ordnet sie zu.")
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .task { me = try? await app.api.authMe() }
            .task { feed = try? await app.api.feedSubscribe() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }
}
