import SwiftUI

/// Base-URL in UserDefaults, API-Key im Keychain. Auth-Zustand über `isConfigured`.
@MainActor
final class Settings: ObservableObject {
    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: "baseURL") }
    }
    @Published private(set) var apiKey: String?

    init() {
        baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? AppConfig.defaultBaseURL
        apiKey = Keychain.read("apiKey")
    }

    var isConfigured: Bool { !(apiKey ?? "").isEmpty && !baseURL.isEmpty }

    func setAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.write("apiKey", value: trimmed)
        apiKey = trimmed
    }

    func logout() {
        Keychain.delete("apiKey")
        apiKey = nil
    }
}
