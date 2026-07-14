import Foundation

/// Anbindung des Trauerkarten-Bereichs an die generischen v1-Ressourcen (Envelope `{data:[…]}`).
/// CompatClient stellt `/api` voran → Pfade beginnen mit `/v1/…`.
@MainActor
final class TrauerkartenAPI {
    private let c: CompatClient
    init(settings: Settings) { c = CompatClient(settings: settings) }

    // MARK: - Laden
    func fetchKarten() async throws -> [Trauerkarte] {
        let obj = try await c.getObject("/v1/trauerkarten", query: [
            URLQueryItem(name: "limit", value: "500"),
            URLQueryItem(name: "sort", value: "created_at:asc"),
        ])
        return ((obj["data"] as? [[String: Any]]) ?? []).map(Trauerkarte.init(fields:))
    }
    func fetchPersonen() async throws -> [TrauerPerson] {
        let obj = try await c.getObject("/v1/trauerkarten-personen", query: [
            URLQueryItem(name: "limit", value: "200"),
            URLQueryItem(name: "sort", value: "id:asc"),
        ])
        return ((obj["data"] as? [[String: Any]]) ?? []).map(TrauerPerson.init(fields:))
    }
    func fetchKosten() async throws -> [KostenEintrag] {
        let obj = try await c.getObject("/v1/trauerkarten-kosten", query: [
            URLQueryItem(name: "limit", value: "500"),
            URLQueryItem(name: "sort", value: "datum:desc"),
        ])
        return ((obj["data"] as? [[String: Any]]) ?? []).map(KostenEintrag.init(fields:))
    }

    // MARK: - Karten
    @discardableResult
    func createKarte(_ b: [String: Any]) async throws -> Trauerkarte {
        Trauerkarte(fields: try await c.send("/v1/trauerkarten", method: "POST", body: b))
    }
    func updateKarte(_ id: Int, _ b: [String: Any]) async throws { _ = try await c.send("/v1/trauerkarten/\(id)", method: "PATCH", body: b) }
    func deleteKarte(_ id: Int) async throws { _ = try await c.send("/v1/trauerkarten/\(id)", method: "DELETE") }

    // MARK: - Kosten
    @discardableResult
    func createKosten(_ b: [String: Any]) async throws -> KostenEintrag {
        KostenEintrag(fields: try await c.send("/v1/trauerkarten-kosten", method: "POST", body: b))
    }
    func updateKosten(_ id: Int, _ b: [String: Any]) async throws { _ = try await c.send("/v1/trauerkarten-kosten/\(id)", method: "PATCH", body: b) }
    func deleteKosten(_ id: Int) async throws { _ = try await c.send("/v1/trauerkarten-kosten/\(id)", method: "DELETE") }

    // MARK: - Personen
    @discardableResult
    func createPerson(_ name: String) async throws -> TrauerPerson {
        TrauerPerson(fields: try await c.send("/v1/trauerkarten-personen", method: "POST", body: ["name": name]))
    }
    func updatePerson(_ id: Int, name: String) async throws { _ = try await c.send("/v1/trauerkarten-personen/\(id)", method: "PATCH", body: ["name": name]) }
    func deletePerson(_ id: Int) async throws { _ = try await c.send("/v1/trauerkarten-personen/\(id)", method: "DELETE") }

    // MARK: - Foto anhängen (Media-Upload setzt foto_key/beleg_key des Datensatzes)
    func attachPhoto(resource: String, id: Int, jpeg: Data) async throws {
        let dataURL = "data:image/jpeg;base64," + jpeg.base64EncodedString()
        _ = try await c.send("/v1/media/upload", method: "POST",
                             body: ["area": "trauerkarten", "resource": resource, "id": id, "data_url": dataURL])
    }

    // MARK: - KI-Scan (token-gated; wirft APIError bei 501 ohne OPENAI_API_KEY)
    func scan(jpeg: Data) async throws -> [String: Any] {
        let dataURL = "data:image/jpeg;base64," + jpeg.base64EncodedString()
        return try await c.send("/v1/trauerkarten-scan", method: "POST", body: ["image": dataURL])
    }
}
