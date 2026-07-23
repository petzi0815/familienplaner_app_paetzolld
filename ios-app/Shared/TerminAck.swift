import Foundation

/// Termin quittieren — **bewusst ohne jede Abhängigkeit zu AppState/APIClient**, damit es in ALLEN
/// drei Kontexten funktioniert: Widget-Extension (interaktiver Button), App im Hintergrund
/// (Mitteilungs-Aktion vom Sperrbildschirm, ohne verbundene Scene) und App im Vordergrund.
///
/// Hintergrund: Die Mitteilungs-Aktionen sind absichtlich NICHT `.foreground` registriert — iOS
/// startet die App dafür nur in den Hintergrund, `AppDelegate.appState` ist dann nil (es wird
/// ausschließlich in `.onAppear` der Root-View gesetzt). Ein Ack über AppState wäre genau im
/// beworbenen Fall („quittieren, ohne die App zu öffnen") ein No-Op.
enum TerminAck {
    enum Action: String {
        case gelesen, erledigt, stumm, laut
    }

    /// Quittierung an `POST /api/termine/{id}/ack` senden.
    /// - Returns: true bei HTTP 2xx. Wirft nie — Aufrufer sind UI-Kontexte, die nicht scheitern dürfen.
    @discardableResult
    static func send(terminId: Int, action: Action, timeout: TimeInterval = 6) async -> Bool {
        guard var req = SharedStore.request("/api/termine/\(terminId)/ack", method: "POST") else { return false }
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["action": action.rawValue])
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let code = (resp as? HTTPURLResponse)?.statusCode else { return false }
        return (200...299).contains(code)
    }
}
