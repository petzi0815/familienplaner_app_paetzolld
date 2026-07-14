import Foundation

/// Auth-fähiger Client für die LEGACY-KOMPAT-Endpunkte unter `/api/<…>` (NICHT `/api/v1`).
/// Diese spiegeln die Original-Bereichsseiten (Samu, Garten, Geschenkplaner) und liefern je nach
/// Modus **bare Arrays** (`[…]`) oder Objekte — anders als die v1-API mit `{data:[…]}`-Envelope.
/// Auth = derselbe Bearer-Key wie überall (guard(): Lesen readonly+, Schreiben agent+).
@MainActor
final class CompatClient {
    let settings: Settings
    init(settings: Settings) { self.settings = settings }

    private var base: String {
        settings.baseURL.hasSuffix("/") ? String(settings.baseURL.dropLast()) : settings.baseURL
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 25
        return URLSession(configuration: c)
    }()

    private func req(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil) throws -> URLRequest {
        guard var comps = URLComponents(string: base + "/api" + path) else { throw APIError(status: 0, message: "Ungültige URL") }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError(status: 0, message: "Ungültige URL") }
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.httpBody = body
        if body != nil { r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        guard let key = settings.apiKey, !key.isEmpty else { throw APIError(status: 401, message: "Nicht angemeldet") }
        r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return r
    }

    private func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        // Kompat-Fehler kommen als {error:"string"} ODER {error:{code,message}} — beides tolerant lesen.
        var msg = ""
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let s = obj["error"] as? String { msg = s }
            else if let e = obj["error"] as? [String: Any], let m = e["message"] as? String { msg = m }
        }
        throw APIError(status: http.statusCode, message: msg)
    }

    // MARK: - Lesen

    /// Bare-Array-Antwort aus Objekten (`[{…},{…}]`).
    func getArray(_ path: String, query: [URLQueryItem] = []) async throws -> [[String: Any]] {
        if let fixture = UITestFixtures.array(path) { return fixture }   // UI-Test: deterministische Daten
        let (data, resp) = try await Self.session.data(for: req(path, query: query))
        try check(resp, data)
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] { return arr }
        return []
    }

    /// Bare-Array-Antwort aus Strings (`["a","b"]` — z.B. ?arten=true / ?kategorien=true).
    func getStrings(_ path: String, query: [URLQueryItem] = []) async throws -> [String] {
        let (data, resp) = try await Self.session.data(for: req(path, query: query))
        try check(resp, data)
        let any = try? JSONSerialization.jsonObject(with: data)
        if let arr = any as? [String] { return arr }
        if let arr = any as? [Any] { return arr.compactMap { $0 as? String } }
        return []
    }

    /// Roh-Bytes eines Endpunkts (Datei-Download, z.B. epub aus Calibre). Wirft bei != 2xx.
    func downloadData(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        let (data, resp) = try await Self.session.data(for: req(path, query: query))
        try check(resp, data)
        return data
    }

    /// Objekt-Antwort (`{…}` — z.B. ?stats=true, /gts, /dashboard, Einzel-GET).
    func getObject(_ path: String, query: [URLQueryItem] = []) async throws -> [String: Any] {
        if let fixture = UITestFixtures.object(path) { return fixture }   // UI-Test: deterministische Daten
        let (data, resp) = try await Self.session.data(for: req(path, query: query))
        try check(resp, data)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    // MARK: - Schreiben

    @discardableResult
    func send(_ path: String, method: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        let data = body.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        let (respData, resp) = try await Self.session.data(for: req(path, method: method, body: data))
        try check(resp, respData)
        return (try? JSONSerialization.jsonObject(with: respData)) as? [String: Any] ?? [:]
    }

    /// Schreiben mit einem Array als Body (z.B. PUT /kinder/{id}/anlaesse — bare array).
    @discardableResult
    func sendArrayBody(_ path: String, method: String, body: [[String: Any]]) async throws -> [[String: Any]] {
        let data = try? JSONSerialization.data(withJSONObject: body)
        let (respData, resp) = try await Self.session.data(for: req(path, method: method, body: data))
        try check(resp, respData)
        return (try? JSONSerialization.jsonObject(with: respData)) as? [[String: Any]] ?? []
    }
}
