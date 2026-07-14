import SwiftUI
import WidgetKit

/// Base-URL in UserDefaults, API-Key im Keychain. Auth-Zustand über `isConfigured`.
/// Spiegelt Base-URL + Key zusätzlich in den App-Group-Store (SharedStore),
/// damit die Widget-Extension das Dashboard laden kann.
@MainActor
final class Settings: ObservableObject {
    @Published var baseURL: String {
        didSet {
            UserDefaults.standard.set(baseURL, forKey: "baseURL")
            SharedStore.baseURL = baseURL
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    @Published private(set) var apiKey: String?

    init() {
        baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? AppConfig.defaultBaseURL
        apiKey = Keychain.read("apiKey")
        // UI-Test: Login überspringen (in-memory, NICHT in die Keychain schreiben).
        if UITestMode.isActive {
            baseURL = UITestMode.baseURL
            apiKey = UITestMode.apiKey
        }
        // Spiegel für die Extension aktuell halten.
        SharedStore.baseURL = baseURL
        SharedStore.apiKey = apiKey
    }

    var isConfigured: Bool { !(apiKey ?? "").isEmpty && !baseURL.isEmpty }

    func setAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.write("apiKey", value: trimmed)
        apiKey = trimmed
        SharedStore.apiKey = trimmed
        SharedStore.baseURL = baseURL
        WidgetCenter.shared.reloadAllTimelines()
    }

    func logout() {
        Keychain.delete("apiKey")
        apiKey = nil
        SharedStore.clearKey()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
