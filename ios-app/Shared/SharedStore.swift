import Foundation

/// Von App UND Widget-Extension geteilter Konfig-Speicher (App Group).
/// Base-URL + API-Key liegen hier, damit die Widget-Timeline das Dashboard abrufen kann.
/// (Bewusster Kompromiss: der Key liegt zusätzlich im App-Group-Store, nicht nur im
/// Schlüsselbund — nötig, damit die Extension ihn lesen kann. Gerätelokal, Familien-App.)
enum SharedStore {
    static let appGroup = "group.app.yagemi.familienplaner"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static var baseURL: String? {
        get { defaults?.string(forKey: "baseURL") }
        set { defaults?.set(newValue, forKey: "baseURL") }
    }
    static var apiKey: String? {
        get { defaults?.string(forKey: "apiKey") }
        set { defaults?.set(newValue, forKey: "apiKey") }
    }
    static func clearKey() { defaults?.removeObject(forKey: "apiKey") }
}
