import Foundation

/// Kompakter Zustand für die Widgets (bewusst eigenständig, nur SharedStore geteilt).
struct WidgetSnapshot {
    var termineTitel: String?
    var termineDatum: String?
    var remindersDue: Int = 0
    var fotoInboxNeu: Int = 0
    var mhdCount: Int = 0
    var nextTripTitle: String?
    var nextTripDays: Int?
}

enum WidgetAPI {
    /// Lädt /api/v1/dashboard/today mit dem App-Group-Key. Loses JSON-Parsing (keine Snake-Case-Fallen).
    static func fetch() async -> WidgetSnapshot? {
        guard let base = SharedStore.baseURL, let key = SharedStore.apiKey, !key.isEmpty,
              let url = URL(string: base.hasSuffix("/") ? base + "api/v1/dashboard/today" : base + "/api/v1/dashboard/today")
        else { return nil }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 12

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var snap = WidgetSnapshot()
        if let first = (obj["termine_upcoming"] as? [[String: Any]])?.first {
            snap.termineTitel = first["title"] as? String
            snap.termineDatum = first["date"] as? String
        }
        snap.remindersDue = obj["reminders_due"] as? Int ?? 0
        if let counts = obj["counts"] as? [String: Any] {
            snap.fotoInboxNeu = counts["foto_inbox_neu"] as? Int ?? 0
        }
        snap.mhdCount = (obj["vorrat_bald_ablaufend"] as? [[String: Any]])?.count ?? 0
        if let trip = obj["next_trip"] as? [String: Any] {
            snap.nextTripTitle = trip["title"] as? String
            snap.nextTripDays = trip["days_until"] as? Int
        }
        return snap
    }
}
