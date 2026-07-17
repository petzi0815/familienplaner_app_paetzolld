import Foundation

/// Anbindung des Pizza-Bereichs an die generischen v1-Ressourcen (Envelope `{data:[…]}`).
/// CompatClient stellt `/api` voran → Pfade beginnen mit `/v1/…`.
///
/// Das Backend haelt NUR Rezepturen + Notizen — die gesamte Teig-/Zeitplanberechnung liegt in
/// `PizzaCalculator` auf dem Geraet. Hier gibt es daher bewusst keinen Rechen-Endpunkt.
@MainActor
final class PizzaAPI {
    private let c: CompatClient
    init(settings: Settings) { c = CompatClient(settings: settings) }

    // MARK: - Laden

    func fetchRezepte() async throws -> [PizzaRezept] {
        let obj = try await c.getObject("/v1/pizza-rezepte", query: [
            URLQueryItem(name: "limit", value: "200"),
            URLQueryItem(name: "sort", value: "updated_at:desc"),
        ])
        return ((obj["data"] as? [[String: Any]]) ?? []).map(PizzaRezept.init(fields:))
    }

    func fetchNotizen(rezeptId: Int) async throws -> [PizzaNotiz] {
        let obj = try await c.getObject("/v1/pizza-notizen", query: [
            URLQueryItem(name: "rezept_id", value: String(rezeptId)),
            URLQueryItem(name: "limit", value: "200"),
            URLQueryItem(name: "sort", value: "created_at:desc"),
        ])
        return ((obj["data"] as? [[String: Any]]) ?? []).map(PizzaNotiz.init(fields:))
    }

    // MARK: - Rezepturen

    @discardableResult
    func createRezept(_ b: [String: Any]) async throws -> PizzaRezept {
        PizzaRezept(fields: try await c.send("/v1/pizza-rezepte", method: "POST", body: b))
    }
    func updateRezept(_ id: Int, _ b: [String: Any]) async throws {
        _ = try await c.send("/v1/pizza-rezepte/\(id)", method: "PATCH", body: b)
    }
    /// Loescht die Rezeptur; die zugehoerigen Notizen raeumt das Backend per ON DELETE CASCADE mit ab.
    func deleteRezept(_ id: Int) async throws {
        _ = try await c.send("/v1/pizza-rezepte/\(id)", method: "DELETE")
    }

    // MARK: - Notizen

    @discardableResult
    func createNotiz(_ b: [String: Any]) async throws -> PizzaNotiz {
        PizzaNotiz(fields: try await c.send("/v1/pizza-notizen", method: "POST", body: b))
    }
    func deleteNotiz(_ id: Int) async throws {
        _ = try await c.send("/v1/pizza-notizen/\(id)", method: "DELETE")
    }
}
