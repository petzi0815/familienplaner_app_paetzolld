import SwiftUI

/// Einstellungen (Server/Konto/Version) — als Sheet aus dem Bereiche-Tab.
struct SettingsSheet: View {
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var me: AuthMe?

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    LabeledContent("URL", value: settings.baseURL)
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }
}
