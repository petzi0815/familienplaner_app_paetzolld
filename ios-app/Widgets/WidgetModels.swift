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

/// v1-Envelope von `GET /api/v1/widget/termine` — `{ "data": {…}, "total": n }`.
private struct WidgetTermineEnvelope: Decodable {
    let data: WidgetTerminFeed
}

enum WidgetAPI {
    /// Ergebnis von `fetchTermine` — inklusive der Information, ob die Daten aus dem
    /// Offline-Cache stammen (dann zeigt das Widget dezent „Stand HH:MM").
    struct TermineResult {
        let feed: WidgetTerminFeed
        /// true = aus `WidgetCache`, nicht frisch vom Server geladen.
        let fromCache: Bool
        /// Stand der Daten (bei Cache: Zeitpunkt des letzten erfolgreichen Abrufs).
        let stamp: Date?
    }

    /// Lädt den schlanken Termin-Feed `GET /api/v1/widget/termine?days=…`.
    /// Erfolg → Feed landet zusätzlich im `WidgetCache` (App Group).
    /// Fehler/Offline/nicht angemeldet → letzter Cache-Stand (`fromCache = true`).
    /// nil = es gibt weder Netz-Antwort noch einen Cache-Stand.
    static func fetchTermine(days: Int = 14) async -> TermineResult? {
        guard let req = SharedStore.request("/api/v1/widget/termine?days=\(days)") else {
            return cachedTermine()
        }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let env = try? JSONDecoder().decode(WidgetTermineEnvelope.self, from: data)
        else { return cachedTermine() }

        WidgetCache.save(env.data)
        return TermineResult(feed: env.data, fromCache: false, stamp: Date())
    }

    /// Letzter erfolgreich geladener Feed aus der App-Group (Offline-Fallback).
    private static func cachedTermine() -> TermineResult? {
        guard let feed = WidgetCache.load() else { return nil }
        return TermineResult(feed: feed, fromCache: true, stamp: WidgetCache.fetchedAt)
    }

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
