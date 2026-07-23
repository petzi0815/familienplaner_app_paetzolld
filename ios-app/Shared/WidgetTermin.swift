import Foundation

/// Schlankes Termin-Modell für die Widgets — Gegenstück zu `GET /api/v1/widget/termine`.
/// Bewusst eigenständig (die Widget-Extension zieht NICHT die App-Modelle mit).
struct WidgetTermin: Codable, Identifiable, Hashable {
    /// Stabile Feed-ID („termin-12", „abfuhr-3").
    let id: String
    /// termin | abfuhr | reise | reminder
    let source: String
    let refId: Int
    let title: String
    let subtitle: String?
    let location: String?
    let emoji: String
    /// Hex mit führendem `#`.
    let color: String
    /// yyyy-MM-dd
    let date: String
    /// HH:MM (nil = ganztägig)
    let time: String?
    /// Beginn als Unix-Epoch-Sekunden.
    let startAt: Double
    /// Ende als Unix-Epoch-Sekunden (nil = keine Endzeit).
    let endAt: Double?
    let allDay: Bool
    let daysUntil: Int
    let read: Bool
    let muted: Bool

    enum CodingKeys: String, CodingKey {
        case id, source, title, subtitle, location, emoji, color, date, time
        case refId = "ref_id"
        case startAt = "start_at"
        case endAt = "end_at"
        case allDay = "all_day"
        case daysUntil = "days_until"
        case read, muted
    }

    var startDate: Date { Date(timeIntervalSince1970: startAt) }
    var endDate: Date? { endAt.map { Date(timeIntervalSince1970: $0) } }

    /// Exklusives Ende ganztägiger Einträge: Beginn des Tages NACH dem letzten Tag.
    /// Der Feed liefert bei mehrtägigen Einträgen (Reisen, mehrtägige Termine) `end_at` = 00:00
    /// des **Endtages** — der Tag zählt also noch dazu. Die Tagesaddition läuft kalendarisch über
    /// `Calendar` (`+86400` würde an den Zeitumstellungen um eine Stunde danebenliegen).
    private var allDayEnd: Date {
        let cal = Calendar.current
        let lastDay = cal.startOfDay(for: endDate ?? startDate)
        return cal.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay.addingTimeInterval(86400)
    }

    /// Läuft gerade (ganztägige Einträge laufen über ALLE ihre Tage — auch mehrtägige Reisen).
    func isRunning(at now: Date = Date()) -> Bool {
        if allDay { return now >= Calendar.current.startOfDay(for: startDate) && now < allDayEnd }
        let end = endDate ?? startDate.addingTimeInterval(3600)
        return now >= startDate && now < end
    }

    /// Bereits vorbei (Terminende bzw. letztes Tagesende überschritten).
    func isPast(at now: Date = Date()) -> Bool {
        if allDay { return now >= allDayEnd }
        return now >= (endDate ?? startDate.addingTimeInterval(3600))
    }

    /// **Dauerläufer**: ein ganztägiger Eintrag, der an einem FRÜHEREN Tag begonnen hat und noch läuft
    /// (Ferien, Reisen, mehrwöchige Vorsorge-Zeiträume). Solche Einträge sind Hintergrund-Information —
    /// sie dürfen die prominente Position nicht belegen, sonst zeigt das Widget wochenlang „Ganztägig /
    /// Sommerferien" statt des nächsten echten Termins.
    func isLongRunning(at now: Date = Date()) -> Bool {
        allDay && startDate < Calendar.current.startOfDay(for: now) && !isPast(at: now)
    }

    /// Zeitpunkt, nach dem im Widget sortiert und gruppiert wird. Für Dauerläufer der heutige
    /// Tagesbeginn statt des (weit zurückliegenden) Starts — sonst landen sie unter „Do, 9. Jul".
    func relevanceDate(at now: Date = Date()) -> Date {
        max(startDate, Calendar.current.startOfDay(for: now))
    }

    /// Grenzen, an denen sich die Darstellung ändert (für ereignisgenaue Timelines).
    func boundaries() -> [Date] {
        if allDay { return [Calendar.current.startOfDay(for: startDate), allDayEnd] }
        var out = [startDate]
        if let e = endDate { out.append(e) }
        else { out.append(startDate.addingTimeInterval(3600)) }
        return out
    }
}

/// Zähler des Feeds (Server-berechnet, damit das Widget nicht selbst gruppieren muss).
struct WidgetTerminCounts: Codable, Hashable {
    let heute: Int
    let morgen: Int
    let woche: Int
}

/// Antwort-Payload von `GET /api/v1/widget/termine` (Feld `data` des v1-Envelopes).
struct WidgetTerminFeed: Codable, Hashable {
    /// Serverzeit als Unix-Epoch-Sekunden.
    let now: Double
    let owner: String?
    let items: [WidgetTermin]
    let counts: WidgetTerminCounts

    static let empty = WidgetTerminFeed(now: 0, owner: nil, items: [],
                                        counts: WidgetTerminCounts(heute: 0, morgen: 0, woche: 0))
}

/// Letzter erfolgreich geladener Feed in der App-Group — damit das Widget bei Netzfehler
/// nicht leer wird, sondern den letzten Stand mit Zeitstempel zeigt. Wird sowohl von der App
/// (nach `loadDashboard`) als auch vom Widget selbst (nach jedem Fetch) geschrieben.
enum WidgetCache {
    private static let feedKey = "widgetTermineFeed"
    private static let stampKey = "widgetTermineFetchedAt"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: SharedStore.appGroup) }

    static func save(_ feed: WidgetTerminFeed) {
        guard let data = try? JSONEncoder().encode(feed) else { return }
        defaults?.set(data, forKey: feedKey)
        defaults?.set(Date().timeIntervalSince1970, forKey: stampKey)
    }

    static func load() -> WidgetTerminFeed? {
        guard let data = defaults?.data(forKey: feedKey) else { return nil }
        return try? JSONDecoder().decode(WidgetTerminFeed.self, from: data)
    }

    /// Zeitpunkt des letzten erfolgreichen Ladens (nil = noch nie).
    static var fetchedAt: Date? {
        let t = defaults?.double(forKey: stampKey) ?? 0
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static func clear() {
        defaults?.removeObject(forKey: feedKey)
        defaults?.removeObject(forKey: stampKey)
    }
}
