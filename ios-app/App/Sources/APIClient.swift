import UIKit

struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message.isEmpty ? "HTTP \(status)" : message }
}

// ── Multipart (Muster aus dem Referenzprojekt) ──
struct MultipartFile { var field: String; var filename: String; var mime: String; var data: Data }

enum MultipartBody {
    static func make(boundary: String, fields: [String: String], files: [MultipartFile]) -> Data {
        var body = Data()
        func put(_ s: String) { if let d = s.data(using: .utf8) { body.append(d) } }
        for (k, v) in fields {
            put("--\(boundary)\r\n")
            put("Content-Disposition: form-data; name=\"\(k)\"\r\n\r\n")
            put("\(v)\r\n")
        }
        for f in files {
            put("--\(boundary)\r\n")
            put("Content-Disposition: form-data; name=\"\(f.field)\"; filename=\"\(f.filename)\"\r\n")
            put("Content-Type: \(f.mime)\r\n\r\n")
            body.append(f.data)
            put("\r\n")
        }
        put("--\(boundary)--\r\n")
        return body
    }
}

@MainActor
final class APIClient {
    private let settings: Settings
    init(settings: Settings) { self.settings = settings }

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d
    }()

    private var base: String {
        settings.baseURL.hasSuffix("/") ? String(settings.baseURL.dropLast()) : settings.baseURL
    }

    private func request(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil) throws -> URLRequest {
        guard var comps = URLComponents(string: base + "/api/v1" + path) else {
            throw APIError(status: 0, message: "Ungültige Server-URL")
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError(status: 0, message: "Ungültige URL") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        guard let key = settings.apiKey, !key.isEmpty else { throw APIError(status: 401, message: "Nicht angemeldet") }
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func checkStatus(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(status: http.statusCode, message: Self.detail(from: data))
        }
    }

    // Fehlerobjekt der API: { "error": { code, message, details } }
    private static func detail(from data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        if let err = obj["error"] as? [String: Any], let m = err["message"] as? String { return m }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        let (data, resp) = try await Self.session.data(for: request(path, query: query))
        try checkStatus(resp, data)
        return try Self.decoder.decode(T.self, from: data)
    }

    @discardableResult
    private func send(_ path: String, method: String, body: Data? = nil) async throws -> Data {
        let (data, resp) = try await Self.session.data(for: request(path, method: method, body: body))
        try checkStatus(resp, data)
        return data
    }

    // MARK: - Endpunkte

    /// Leichter Auth-Check (für den Login).
    func ping() async throws { _ = try await get("/agent/capabilities", as: EmptyOK.self) }

    func lebensbereiche() async throws -> [Lebensbereich] {
        try await get("/lebensbereiche",
                      query: [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "sort", value: "sort:asc")],
                      as: LebensbereichList.self).data
    }

    func inbox(limit: Int = 50) async throws -> [FotoInboxItem] {
        try await get("/foto-inbox",
                      query: [URLQueryItem(name: "sort", value: "id:desc"), URLQueryItem(name: "limit", value: String(limit))],
                      as: FotoInboxList.self).data
    }

    /// Foto in den Foto-Eingang hochladen (multipart) → foto_inbox status='neu'.
    func uploadFoto(jpeg: Data, bereich: String?, notiz: String?) async throws -> FotoUploadResult {
        guard let key = settings.apiKey, !key.isEmpty else { throw APIError(status: 401, message: "Nicht angemeldet") }
        guard let url = URL(string: base + "/api/v1/foto/upload") else { throw APIError(status: 0, message: "Ungültige URL") }

        var fields: [String: String] = ["quelle": "ios"]
        if let bereich, !bereich.isEmpty { fields["bereich"] = bereich }
        if let notiz, !notiz.isEmpty { fields["notiz"] = notiz }
        fields["aufgenommen_am"] = ISO8601DateFormatter().string(from: Date())

        let file = MultipartFile(field: "file", filename: "foto.jpg", mime: "image/jpeg", data: jpeg)
        let boundary = "fp-" + UUID().uuidString
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = MultipartBody.make(boundary: boundary, fields: fields, files: [file])

        // URLSession.shared (60s) statt der knappen JSON-Session — Uploads dauern länger.
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkStatus(resp, data)
        return try Self.decoder.decode(FotoUploadResult.self, from: data)
    }

    /// APNs-Device-Token registrieren.
    func registerPush(token: String) async throws {
        #if DEBUG
        let env = "sandbox"
        #else
        let env = "production"
        #endif
        let body = try JSONSerialization.data(withJSONObject: ["token": token, "environment": env])
        _ = try await send("/push/register", method: "POST", body: body)
    }

    /// Media (Thumbnails) auth-bewusst laden — /api/v1/media/… braucht den Bearer-Header.
    func loadMedia(pathOrUrl: String) async throws -> Data {
        let full = pathOrUrl.hasPrefix("http") ? pathOrUrl : base + pathOrUrl
        guard let url = URL(string: full) else { throw APIError(status: 0, message: "Ungültige URL") }
        var req = URLRequest(url: url)
        if let key = settings.apiKey { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await Self.session.data(for: req)
        try checkStatus(resp, data)
        return data
    }
}

struct EmptyOK: Decodable {}
