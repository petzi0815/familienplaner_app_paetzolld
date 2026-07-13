import Foundation

/// Backend-Anbindung des Garten-Bereichs an die Kompat-Endpunkte `/api/garten/*`.
/// Non-REST-Eigenheiten: Dünger-Update = `{id}` im BODY (PUT ohne Pfad), Dünger-Delete = `?id=` im QUERY.
@MainActor
final class GartenAPI {
    private let c: CompatClient
    init(settings: Settings) { c = CompatClient(settings: settings) }

    // ── Stats / Arten / GTS ──
    func fetchStats() async throws -> GartenStats {
        GartenStats(object: try await c.getObject("/garten/stats"))
    }

    func fetchArten() async throws -> [String] {
        try await c.getStrings("/garten/pflanzen", query: [.init(name: "arten", value: "true")])
    }

    func fetchGts() async throws -> GTSResult {
        GTSResult(object: try await c.getObject("/garten/gts"))
    }

    // ── Pflanzen ──
    func fetchPflanzen(_ f: GartenPflanzenFilter) async throws -> [GartenPflanze] {
        var q: [URLQueryItem] = [.init(name: "status", value: "aktiv")]
        if let a = f.art, !a.isEmpty { q.append(.init(name: "art", value: a)) }
        if let b = f.bewaesserung, !b.isEmpty { q.append(.init(name: "bewaesserung", value: b)) }
        if !f.search.isEmpty { q.append(.init(name: "search", value: f.search)) }
        return try await c.getArray("/garten/pflanzen", query: q).map(GartenPflanze.init(fields:))
    }

    // ── Samen ──
    func fetchSamen(_ f: GartenSamenFilter) async throws -> [GartenSamen] {
        var q: [URLQueryItem] = []
        if f.aktiv != -1 { q.append(.init(name: "aktiv", value: String(f.aktiv))) }
        if !f.search.isEmpty { q.append(.init(name: "search", value: f.search)) }
        if !f.hersteller.isEmpty { q.append(.init(name: "hersteller", value: f.hersteller)) }
        if !f.bio.isEmpty { q.append(.init(name: "bio", value: f.bio)) }
        if !f.typ.isEmpty { q.append(.init(name: "typ", value: f.typ)) }
        if f.samenfest != -1 { q.append(.init(name: "samenfest", value: String(f.samenfest))) }
        if !f.keimfaehig.isEmpty { q.append(.init(name: "keimfaehig", value: f.keimfaehig)) }
        return try await c.getArray("/garten/samen", query: q).map(GartenSamen.init(fields:))
    }

    @discardableResult
    func addSamen(nummer: String, name: String) async throws -> Int {
        let r = try await c.send("/garten/samen", method: "POST", body: ["nummer": nummer, "name": name, "aktiv": 1])
        return Coerce.int(r["id"]) ?? 0
    }

    func setSamenAktiv(_ id: Int, _ v: Bool) async throws {
        _ = try await c.send("/garten/samen/\(id)", method: "PUT", body: ["aktiv": v ? 1 : 0])
    }

    func deleteSamen(_ id: Int) async throws {
        _ = try await c.send("/garten/samen/\(id)", method: "DELETE")
    }

    // ── Dünger ──
    func fetchDuenger(_ f: GartenDuengerFilter) async throws -> [GartenDuenger] {
        var q: [URLQueryItem] = []
        if !f.typ.isEmpty { q.append(.init(name: "typ", value: f.typ)) }
        if f.vorraetig != -1 { q.append(.init(name: "vorraetig", value: String(f.vorraetig))) }
        if !f.search.isEmpty { q.append(.init(name: "search", value: f.search)) }
        return try await c.getArray("/garten/duenger", query: q).map(GartenDuenger.init(fields:))
    }

    @discardableResult
    func addDuenger(name: String) async throws -> Int {
        let r = try await c.send("/garten/duenger", method: "POST", body: ["name": name, "vorraetig": 1])
        return Coerce.int(r["id"]) ?? 0
    }

    /// Non-REST: id steht im BODY (kein Pfad-Parameter).
    func setDuengerVorraetig(_ id: Int, _ v: Bool) async throws {
        _ = try await c.send("/garten/duenger", method: "PUT", body: ["id": id, "vorraetig": v ? 1 : 0])
    }

    /// Non-REST: id steht im QUERY-String.
    func deleteDuenger(_ id: Int) async throws {
        _ = try await c.send("/garten/duenger?id=\(id)", method: "DELETE")
    }

    // ── Aufgaben ──
    func fetchAufgaben(_ f: GartenAufgabenFilter) async throws -> [GartenAufgabe] {
        var q: [URLQueryItem] = [.init(name: "jahr", value: "2026")]
        if f.erledigt != -1 { q.append(.init(name: "erledigt", value: String(f.erledigt))) }
        if f.bereich != "alle" { q.append(.init(name: "bereich", value: f.bereich)) }
        return try await c.getArray("/garten/aufgaben", query: q).map(GartenAufgabe.init(fields:))
    }

    func setAufgabeErledigt(_ id: Int, _ v: Bool) async throws {
        _ = try await c.send("/garten/aufgaben/\(id)", method: "PUT", body: ["erledigt": v ? 1 : 0])
    }

    func setAufgabeMonat(_ id: Int, _ monat: Int) async throws {
        _ = try await c.send("/garten/aufgaben/\(id)", method: "PUT", body: ["geplant_monat": monat])
    }
}
