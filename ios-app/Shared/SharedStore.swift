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
    /// Person hinter dem Login-Key ("lars" | "elita" | nil) — das Widget zeigt damit an,
    /// wer einen Termin quittiert hat, ohne selbst /auth/me abzufragen.
    static var owner: String? {
        get { defaults?.string(forKey: "owner") }
        set { defaults?.set(newValue, forKey: "owner") }
    }
    static func clearKey() {
        defaults?.removeObject(forKey: "apiKey")
        defaults?.removeObject(forKey: "owner")
    }

    /// Vollständige URL zu einem API-Pfad (führender Slash), oder nil wenn nicht konfiguriert.
    static func url(_ path: String) -> URL? {
        guard let base = baseURL, !base.isEmpty else { return nil }
        return URL(string: base.hasSuffix("/") ? String(base.dropLast()) + path : base + path)
    }

    /// Authentifizierte Anfrage (Bearer aus der App-Group). nil = nicht angemeldet.
    static func request(_ path: String, method: String = "GET") -> URLRequest? {
        guard let url = url(path), let key = apiKey, !key.isEmpty else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 12
        return req
    }
}
