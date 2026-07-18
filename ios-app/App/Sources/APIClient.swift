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

    /// Angemeldete Identität (Rolle + owner) — zeigt, als wer der Key gilt.
    func authMe() async throws -> AuthMe { try await get("/auth/me", as: AuthMe.self) }

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

    /// Kompakter Tageszustand fürs „Heute"-Dashboard.
    func dashboard() async throws -> DashboardToday {
        if let data = UITestFixtures.dashboardData {
            return try Self.decoder.decode(DashboardToday.self, from: data)
        }
        return try await get("/dashboard/today", as: DashboardToday.self)
    }

    /// Abo-URL des Familien-Kalender-Feeds (https + webcal). Legt den Token serverseitig bei Bedarf an.
    func feedSubscribe() async throws -> FeedSubscribeInfo {
        if let data = UITestFixtures.feedSubscribeData {
            return try Self.decoder.decode(FeedSubscribeInfo.self, from: data)
        }
        return try await get("/feed/subscribe", as: FeedSubscribeInfo.self)
    }

    /// Status der Alarmo-Alarmanlage (Home Assistant). Nie-erreichbar → reachable:false (kein Throw serverseitig).
    func alarmoStatus() async throws -> AlarmoStatus {
        if let data = UITestFixtures.alarmoData {
            return try Self.decoder.decode(AlarmoStatus.self, from: data)
        }
        return try await get("/alarmo", as: AlarmoStatus.self)
    }

    /// Alarmo scharf/unscharf schalten (PIN liegt serverseitig). action = arm_away|arm_home|arm_night|arm_vacation|disarm.
    /// Gibt den frisch gelesenen Status nach der Aktion zurück.
    @discardableResult
    func alarmoAction(_ action: String) async throws -> AlarmoStatus {
        let body = try JSONSerialization.data(withJSONObject: ["action": action])
        let data = try await send("/alarmo", method: "POST", body: body)
        return try Self.decoder.decode(AlarmoStatus.self, from: data)
    }

    /// Haus-Steuerung: Raffstore-Zustände + Szenen-Scripts (Home Assistant, kuratiert).
    func houseState() async throws -> HouseData {
        if let data = UITestFixtures.houseData {
            return try Self.decoder.decode(HouseData.self, from: data)
        }
        return try await get("/smarthome/house", as: HouseData.self)
    }

    /// Raffstore steuern. action = open|close|stop|set_position|set_tilt|open_tilt|close_tilt|stop_tilt.
    /// value (0–100) nur bei set_position/set_tilt. Gibt den frisch gelesenen Haus-Zustand zurück.
    @discardableResult
    func coverAction(entity: String, action: String, value: Int? = nil) async throws -> HouseData {
        var payload: [String: Any] = ["entity": entity, "action": action]
        if let value { payload["value"] = value }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await send("/smarthome/cover", method: "POST", body: body)
        return try Self.decoder.decode(HouseData.self, from: data)
    }

    /// Szenen-Script starten (bringt alle Raffstores in eine Position).
    func runScript(entity: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["entity": entity])
        _ = try await send("/smarthome/script", method: "POST", body: body)
    }

    /// Kuratierte Kameraliste (über Home Assistant).
    func cameras() async throws -> CameraList {
        if let data = UITestFixtures.camerasData {
            return try Self.decoder.decode(CameraList.self, from: data)
        }
        return try await get("/smarthome/cameras", as: CameraList.self)
    }

    /// Aktueller Kamera-Schnappschuss (JPEG, auth-bewusst; Cache-Buster erzwingt frisches Bild).
    func cameraSnapshot(entity: String) async throws -> Data {
        let ts = String(Int(Date().timeIntervalSince1970))
        let req = try request("/smarthome/cameras/\(entity)/snapshot", query: [URLQueryItem(name: "t", value: ts)])
        let (data, resp) = try await Self.session.data(for: req)
        try checkStatus(resp, data)
        return data
    }

    /// Live-HLS-URL einer Kamera (direkt von HA abspielbar → AVPlayer).
    func cameraStreamURL(entity: String) async throws -> URL {
        let s = try await get("/smarthome/cameras/\(entity)/stream", as: CameraStream.self)
        guard let u = URL(string: s.url) else { throw APIError(status: 0, message: "Ungültige Stream-URL") }
        return u
    }

    /// Neuester bekannter iOS-Build (TestFlight) — fürs Update-Banner.
    func appVersion() async throws -> AppVersionInfo {
        if let data = UITestFixtures.appVersionData {
            return try Self.decoder.decode(AppVersionInfo.self, from: data)
        }
        return try await get("/app/version", as: AppVersionInfo.self)
    }

    /// Kommende Abfuhrtermine je Kategorie gruppiert (für die native Kalenderansicht).
    func abfuhrCalendar() async throws -> [AbfuhrGroup] {
        try await get("/abfuhr/calendar", as: AbfuhrCalendarResponse.self).groups
    }

    /// Termine online von aha-region.de neu ziehen (Agent-Rolle). Gibt Anzahl importierter Termine zurück.
    @discardableResult
    func syncAbfuhr() async throws -> Int {
        let data = try await send("/abfuhr/sync-aha", method: "POST")
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return (obj?["upserted"] as? Int) ?? 0
    }

    /// Ressourcenübergreifende Volltextsuche.
    func search(_ q: String) async throws -> SearchResponse {
        try await get("/search", query: [URLQueryItem(name: "q", value: q)], as: SearchResponse.self)
    }

    func trips(limit: Int = 50) async throws -> [Trip] {
        try await get("/reisen",
                      query: [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "sort", value: "start_date:desc")],
                      as: TripList.self).data
    }

    func tripActivities(tripId: Int) async throws -> [TripActivity] {
        try await get("/reisen-activities",
                      query: [URLQueryItem(name: "trip_id", value: String(tripId)), URLQueryItem(name: "limit", value: "200")],
                      as: TripActivityList.self).data
    }

    /// Generischer Insert (POST /api/v1/<resource>) — Felder müssen echte Spalten sein.
    @discardableResult
    func createRecord(_ resource: String, fields: [String: Any]) async throws -> [String: Any] {
        let body = try JSONSerialization.data(withJSONObject: fields)
        let data = try await send("/\(resource)", method: "POST", body: body)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// Aufgabe abhaken. Serverseitig recurring-aware: einmalige → erledigt, wiederholende rücken auf
    /// die nächste Fälligkeit vor. (Garten-Aufgaben laufen dagegen über patchRecord("garten-aufgaben").)
    func completeAufgabe(id: Int) async throws {
        _ = try await send("/aufgaben/\(id)/complete", method: "POST")
    }

    /// Maschinenlesbarer Ressourcen-Index (alle Bereiche + Spalten + Bild-Spec).
    func capabilities() async throws -> [ResourceInfo] {
        try await get("/agent/capabilities", as: Capabilities.self).resources
    }

    /// Generische Liste (Rohwerte, dynamische Spalten) — für den Bereiche-Browser.
    /// `filter` = exakte Spaltenfilter (z.B. ["trip_id": "5"]).
    func listRecords(_ resource: String, primaryKey: String, search: String? = nil,
                     filter: [String: String] = [:], limit: Int = 200) async throws -> [GenericRecord] {
        var q = [URLQueryItem(name: "limit", value: String(limit))]
        if let s = search, !s.isEmpty { q.append(URLQueryItem(name: "search", value: s)) }
        for (k, v) in filter { q.append(URLQueryItem(name: k, value: v)) }
        let (data, resp) = try await Self.session.data(for: request("/\(resource)", query: q))
        try checkStatus(resp, data)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let arr = (obj?["data"] as? [[String: Any]]) ?? []
        return arr.map { row in
            let idStr = row[primaryKey].map { fieldString($0) } ?? UUID().uuidString
            return GenericRecord(id: idStr, fields: row)
        }
    }

    /// Einzelnen Datensatz laden (z.B. aus einem Suchtreffer).
    func getRecord(_ resource: String, id: String) async throws -> GenericRecord {
        let (data, resp) = try await Self.session.data(for: request("/\(resource)/\(id)"))
        try checkStatus(resp, data)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return GenericRecord(id: id, fields: obj)
    }

    /// Teil-Update (Schnellaktion, z.B. Status-PATCH).
    func patchRecord(_ resource: String, id: String, fields: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: fields)
        _ = try await send("/\(resource)/\(id)", method: "PATCH", body: body)
    }

    /// Bücher-Regale (für die Regal-Auswahl beim Buch-Anlegen). Nutzt das Bookshelf aus dem ElisBooks-Modul.
    func bookshelves() async throws -> [Bookshelf] {
        let recs = try await listRecords("elisbooks-bookshelves", primaryKey: "id", limit: 100)
        return recs.map { Bookshelf(fields: $0.fields) }
    }

    // MARK: - Fotobox

    /// Kontextabhängige Vorschlagsfelder je Domäne (für die Picker nach dem Foto).
    func fotoboxForms() async throws -> [FotoboxDomainForm] {
        try await get("/fotobox-items/form-config", as: FotoboxFormConfig.self).domains
    }

    /// Erlaubte Intent-Werte (aus dem Fotobox-Schema, dynamisch aus fotobox_labels).
    func fotoboxIntents() async throws -> [String] {
        let (data, resp) = try await Self.session.data(for: request("/fotobox-items/schema"))
        try checkStatus(resp, data)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let allowed = obj?["allowed"] as? [String: Any]
        return (allowed?["intent"] as? [String]) ?? []
    }

    /// Ein Fotobox-Item anlegen (routing + analysis_hint + inline-Foto). Gibt die Server-Antwort zurück.
    @discardableResult
    func createFotoboxItem(_ payload: [String: Any]) async throws -> [String: Any] {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await send("/fotobox-items", method: "POST", body: body)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
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
struct FeedSubscribeInfo: Decodable { let url: String; let webcal: String }
