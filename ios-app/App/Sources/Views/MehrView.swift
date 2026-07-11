import SwiftUI

/// „Mehr"-Hub: weitere Lebensbereiche (Reisen-Karte) + Konto/Server.
struct MehrView: View {
    @EnvironmentObject private var settings: Settings

    var body: some View {
        NavigationStack {
            List {
                Section("Lebensbereiche") {
                    NavigationLink { ReiseListView() } label: {
                        Label("Reisen (Karte)", systemImage: "map.fill")
                    }
                }
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
                    Text("Familienplaner – Fotos, Termine, Bücher, Vorräte und mehr. Der Agent Ole analysiert Uploads und ordnet sie zu.")
                }
            }
            .navigationTitle("Mehr")
        }
    }
}
