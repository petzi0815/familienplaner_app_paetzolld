import Foundation

/// Backend-Anbindung des Geschenkplaners an die Kompat-Endpunkte `/api/geschenkplaner/*`.
/// Listen = bare Arrays, Dashboard/Einzel-GET = Objekte, PUT anlaesse = bare Array als Body.
@MainActor
final class GeschenkAPI {
    private let c: CompatClient
    init(settings: Settings) { c = CompatClient(settings: settings) }

    private let base = "/geschenkplaner"

    // MARK: - Dashboard
    func dashboard() async throws -> GDashboard {
        GDashboard(object: try await c.getObject("\(base)/dashboard"))
    }

    // MARK: - Kinder
    func kinder() async throws -> [GKind] {
        try await c.getArray("\(base)/kinder").map(GKind.init(fields:))
    }

    func kind(_ id: Int) async throws -> GKind {
        GKind(fields: try await c.getObject("\(base)/kinder/\(id)"))
    }

    @discardableResult
    func createKind(_ body: [String: Any]) async throws -> Int {
        let r = try await c.send("\(base)/kinder", method: "POST", body: body)
        return Coerce.int(r["id"]) ?? 0
    }

    func updateKind(_ id: Int, _ body: [String: Any]) async throws {
        _ = try await c.send("\(base)/kinder/\(id)", method: "PATCH", body: body)
    }

    func deleteKind(_ id: Int) async throws {
        _ = try await c.send("\(base)/kinder/\(id)", method: "DELETE")
    }

    func confirmProfil(_ id: Int) async throws {
        _ = try await c.send("\(base)/kinder/\(id)/profil-bestaetigen", method: "POST")
    }

    // MARK: - Anlaesse
    func anlaesse(_ kindId: Int) async throws -> [GAnlassConfig] {
        try await c.getArray("\(base)/kinder/\(kindId)/anlaesse").map(GAnlassConfig.init(fields:))
    }

    @discardableResult
    func putAnlaesse(_ kindId: Int, configs: [[String: Any]]) async throws -> [GAnlassConfig] {
        try await c.sendArrayBody("\(base)/kinder/\(kindId)/anlaesse", method: "PUT", body: configs).map(GAnlassConfig.init(fields:))
    }

    // MARK: - Ereignisse
    func ereignisse(kindId: Int? = nil) async throws -> [GEreignis] {
        var q: [URLQueryItem] = []
        if let k = kindId { q.append(.init(name: "kind_id", value: String(k))) }
        return try await c.getArray("\(base)/ereignisse", query: q).map(GEreignis.init(fields:))
    }

    func ereignis(_ id: Int) async throws -> GEreignis {
        GEreignis(fields: try await c.getObject("\(base)/ereignisse/\(id)"))
    }

    func patchEreignisReminder(_ id: Int, aktiv: Int) async throws {
        _ = try await c.send("\(base)/ereignisse/\(id)", method: "PATCH", body: ["erinnerungen_aktiv": aktiv])
    }

    func generieren() async throws {
        _ = try await c.send("\(base)/ereignisse/generieren", method: "POST")
    }

    // MARK: - Geschenke
    func geschenke(ereignisId: Int? = nil, kindId: Int? = nil, status: [String] = []) async throws -> [GGeschenk] {
        var q: [URLQueryItem] = []
        if let e = ereignisId { q.append(.init(name: "ereignis_id", value: String(e))) }
        if let k = kindId { q.append(.init(name: "kind_id", value: String(k))) }
        for s in status { q.append(.init(name: "status", value: s)) }
        return try await c.getArray("\(base)/geschenke", query: q).map(GGeschenk.init(fields:))
    }

    @discardableResult
    func createGeschenk(_ body: [String: Any]) async throws -> Int {
        let r = try await c.send("\(base)/geschenke", method: "POST", body: body)
        return Coerce.int(r["id"]) ?? 0
    }

    func updateGeschenk(_ id: Int, _ body: [String: Any]) async throws {
        _ = try await c.send("\(base)/geschenke/\(id)", method: "PATCH", body: body)
    }

    func deleteGeschenk(_ id: Int) async throws {
        _ = try await c.send("\(base)/geschenke/\(id)", method: "DELETE")
    }

    func vergeben(_ id: Int) async throws {
        _ = try await c.send("\(base)/geschenke/\(id)/vergeben", method: "POST")
    }

    func schonGeschenkt(_ id: Int) async throws {
        _ = try await c.send("\(base)/geschenke/\(id)/schon-geschenkt", method: "POST")
    }

    // MARK: - Vergangene Geschenke (Archiv)
    func vergangene(kindId: Int? = nil) async throws -> [GVergangenes] {
        var q: [URLQueryItem] = []
        if let k = kindId { q.append(.init(name: "kind_id", value: String(k))) }
        return try await c.getArray("\(base)/vergangene-geschenke", query: q).map(GVergangenes.init(fields:))
    }

    @discardableResult
    func createVergangenes(_ body: [String: Any]) async throws -> Int {
        let r = try await c.send("\(base)/vergangene-geschenke", method: "POST", body: body)
        return Coerce.int(r["id"]) ?? 0
    }

    func deleteVergangenes(_ id: Int) async throws {
        _ = try await c.send("\(base)/vergangene-geschenke/\(id)", method: "DELETE")
    }
}
