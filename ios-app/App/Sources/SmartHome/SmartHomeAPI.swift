import Foundation

/// Backend-Anbindung des Smart-Home-Bereichs an die Kompat-Endpunkte `/api/smarthome/*`.
/// Antworten sind GEWRAPPT (`{entities}`, `{aliases}`, `{relationships}`, `{logs}`, flaches `stats`),
/// daher `getObject` + Array-Extraktion statt `getArray`. Schreiben braucht einen Agent-Key.
/// 501-Endpunkte (prompt/exec/ask) werden bewusst NICHT aufgerufen (externe HA/AI, nicht migriert).
@MainActor
final class SmartHomeAPI {
    private let c: CompatClient
    init(settings: Settings) { c = CompatClient(settings: settings) }

    /// Array unter `key` aus einem gewrappten Objekt tolerant extrahieren.
    private func arr(_ obj: [String: Any], _ key: String) -> [[String: Any]] {
        if let a = obj[key] as? [[String: Any]] { return a }
        if let a = obj[key] as? [Any] { return a.compactMap { $0 as? [String: Any] } }
        return []
    }

    // MARK: - Lesen

    func fetchEntities(_ f: HAEntityFilters) async throws -> [HAEntity] {
        var q: [URLQueryItem] = []
        if let d = f.domain { q.append(.init(name: "domain", value: d)) }
        // `area` bewusst NICHT an den Server (der behandelt area="" als falsy -> liefert ALLES).
        // Raumfilter passiert clientseitig, da ohnehin clientseitig nach Raum gruppiert wird.
        q.append(.init(name: "disabled", value: f.disabled))
        q.append(.init(name: "sort", value: f.sort))
        let obj = try await c.getObject("/smarthome/entities", query: q)
        return arr(obj, "entities").map(HAEntity.init(fields:))
    }

    /// Ungefilterte Gesamtliste (fuer die Beziehungs-Auswahl).
    func fetchAllEntities() async throws -> [HAEntity] {
        let obj = try await c.getObject("/smarthome/entities",
                                        query: [.init(name: "disabled", value: "all"), .init(name: "sort", value: "name")])
        return arr(obj, "entities").map(HAEntity.init(fields:))
    }

    func fetchStats() async throws -> HAStats {
        HAStats(object: try await c.getObject("/smarthome/stats"))
    }

    func fetchAliases() async throws -> [HAAlias] {
        let obj = try await c.getObject("/smarthome/aliases")
        return arr(obj, "aliases").map(HAAlias.init(fields:))
    }

    func fetchRelationships(_ f: HARelationFilters) async throws -> [HARelationship] {
        var q: [URLQueryItem] = []
        if f.type != "all" { q.append(.init(name: "type", value: f.type)) }
        let obj = try await c.getObject("/smarthome/relationships", query: q)
        return arr(obj, "relationships").map(HARelationship.init(fields:))
    }

    func fetchLog(limit: Int = 100) async throws -> [HACommandLog] {
        let obj = try await c.getObject("/smarthome/log", query: [.init(name: "limit", value: String(limit))])
        return arr(obj, "logs").map(HACommandLog.init(fields:))
    }

    // MARK: - Schreiben (Agent-Key noetig; guard() gibt sonst 401/403)

    /// Toggelt das app-lokale `disabled`-Flag; liefert den neuen Wert zurueck.
    @discardableResult
    func toggleDisabled(_ entityId: String) async throws -> Bool {
        let r = try await c.send("/smarthome/entities/toggle-disabled", method: "POST", body: ["entity_id": entityId])
        return Coerce.bool(r["disabled"])
    }

    func addAlias(entityId: String, alias: String) async throws {
        _ = try await c.send("/smarthome/aliases", method: "POST", body: ["entity_id": entityId, "alias": alias])
    }

    /// alias DELETE nimmt `?entity_id=&alias=` in der Query (alias URL-encoded).
    func deleteAlias(entityId: String, alias: String) async throws {
        let path = "/smarthome/aliases?entity_id=\(Self.enc(entityId))&alias=\(Self.enc(alias))"
        _ = try await c.send(path, method: "DELETE")
    }

    func addRelationship(parent: String, child: String, type: String) async throws {
        _ = try await c.send("/smarthome/relationships", method: "POST",
                             body: ["parent_entity_id": parent, "child_entity_id": child, "type": type])
    }

    /// relationships DELETE/PATCH nehmen `?id=` in der Query (nicht als Pfad-Parameter).
    func deleteRelationship(_ id: Int) async throws {
        _ = try await c.send("/smarthome/relationships?id=\(id)", method: "DELETE")
    }

    func setVerified(_ id: Int, _ verified: Bool) async throws {
        _ = try await c.send("/smarthome/relationships?id=\(id)", method: "PATCH",
                             body: ["manually_verified": verified ? 1 : 0])
    }

    /// URL-encodet einen Query-Wert (nur unreservierte Zeichen bleiben stehen).
    private static func enc(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
