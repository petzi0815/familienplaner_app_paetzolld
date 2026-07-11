import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: Settings

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    LabeledContent("URL", value: settings.baseURL)
                }
                Section("Konto") {
                    Button(role: .destructive) {
                        settings.logout()
                    } label: {
                        Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
                Section {
                    LabeledContent("Version", value: "1.0")
                } footer: {
                    Text("Fotos werden an den Familienplaner hochgeladen; der Agent Ole analysiert und ordnet sie den Datensätzen zu.")
                }
            }
            .navigationTitle("Einstellungen")
        }
    }
}
