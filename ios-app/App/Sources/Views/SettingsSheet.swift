import SwiftUI

/// Einstellungen (Server/Konto/Version) — als Sheet aus dem Bereiche-Tab.
struct SettingsSheet: View {
    @EnvironmentObject private var settings: Settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    LabeledContent("URL", value: settings.baseURL)
                }
                Section("Konto") {
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }
}
