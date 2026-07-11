import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var app: AppState

    @State private var baseURL = ""
    @State private var token = ""
    @State private var message = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        BrandMark()
                        Text("Familienplaner").font(.title2.weight(.bold))
                        Text("Fotos aufnehmen & zuordnen").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .listRowBackground(Color.clear)
                }
                Section("Server") {
                    TextField("https://familienplaner.yagemi.app", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)
                }
                Section {
                    SecureField("API-Key", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                } header: {
                    Text("Zugang")
                } footer: {
                    Text("Der API-Key (Rolle agent) wird sicher im Schlüsselbund gespeichert.")
                }
                if !message.isEmpty {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        if busy { ProgressView().padding(.trailing, 4) }
                        Text(busy ? "Verbinde …" : "Verbinden")
                    }
                }
                .disabled(busy || token.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .navigationTitle("Anmelden")
            .onAppear { if baseURL.isEmpty { baseURL = settings.baseURL } }
        }
    }

    private func connect() async {
        busy = true
        message = "Verbinde …"
        let b = baseURL.trimmingCharacters(in: .whitespaces)
        settings.baseURL = b.isEmpty ? AppConfig.defaultBaseURL : b
        settings.setAPIKey(token)
        do {
            try await app.api.ping()
            message = "" // RootView wechselt automatisch (isConfigured == true)
        } catch {
            settings.logout()
            message = "Verbindung fehlgeschlagen. Server-URL & API-Key prüfen."
        }
        busy = false
    }
}
