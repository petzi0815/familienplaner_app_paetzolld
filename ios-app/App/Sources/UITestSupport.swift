import Foundation

/// UI-Test-Modus: die App wird mit `-uitest` (bzw. `UITEST_MODE=1`) gestartet, überspringt den Login
/// (Settings vorbefüllt) und befüllt die Bereiche-Grid statisch aus dem DomainCatalog, damit die
/// Navigation im Simulator OHNE erreichbares Backend deterministisch getestet werden kann.
/// Optional `UITEST_BASE_URL` / `UITEST_API_KEY` für datengetriebene Tests gegen ein echtes Backend.
enum UITestMode {
    static let isActive: Bool = {
        let p = ProcessInfo.processInfo
        return p.arguments.contains("-uitest") || p.environment["UITEST_MODE"] == "1"
    }()

    /// Standard: instant abweisende Adresse → Netzcalls scheitern sofort (kein Prod-Zugriff im Test).
    static var baseURL: String { ProcessInfo.processInfo.environment["UITEST_BASE_URL"] ?? "http://127.0.0.1:1" }
    static var apiKey: String { ProcessInfo.processInfo.environment["UITEST_API_KEY"] ?? "uitest-dummy-key" }
}
