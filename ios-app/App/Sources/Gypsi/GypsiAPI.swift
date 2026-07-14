import Foundation

/// Backend-Anbindung des Gypsi-Futters an die Kompat-Endpunkte `/api/gypsi/futter`.
/// Liste = bare Array (`erfasst_am DESC` serverseitig). Auth = Bearer (Lesen readonly+, Schreiben agent+).
@MainActor
final class GypsiAPI {
    private let c: CompatClient
    init(settings: Settings) { c = CompatClient(settings: settings) }

    /// Vollständige Liste (ungefiltert). Filtern/Stats/Optionen laufen nativ clientseitig
    /// über diese Liste — die DISTINCT-Marken/Geschmäcker der `?marken=true`/`?geschmacksrichtungen=true`
    /// Modi ergeben sich 1:1 aus derselben Tabelle, daher kein zusätzlicher Round-Trip.
    func fetchAll() async throws -> [GypsiFutter] {
        try await c.getArray("/gypsi/futter").map(GypsiFutter.init(fields:))
    }

    /// Neues Futter anlegen. Server setzt `status` default `mag_er`. Antwort: `{id, success}`.
    @discardableResult
    func add(marke: String, sorte: String, geschmack: String?, notizen: String?) async throws -> Int {
        var body: [String: Any] = ["marke": marke, "sorte": sorte]
        if let g = geschmack, !g.isEmpty { body["geschmack"] = g }
        if let n = notizen, !n.isEmpty { body["notizen"] = n }
        let r = try await c.send("/gypsi/futter", method: "POST", body: body)
        return Coerce.int(r["id"]) ?? 0
    }

    /// Status umschalten (einziges mutierbares Feld). Server aktualisiert `status_geaendert_am`.
    func setStatus(_ id: Int, _ status: String) async throws {
        _ = try await c.send("/gypsi/futter/\(id)", method: "PATCH", body: ["status": status])
    }

    func delete(_ id: Int) async throws {
        _ = try await c.send("/gypsi/futter/\(id)", method: "DELETE")
    }
}
