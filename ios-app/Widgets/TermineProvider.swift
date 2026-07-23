import Foundation
import WidgetKit

/// Ein Zeitpunkt der Termin-Timeline.
///
/// **Wichtig:** Alle Entries einer Timeline entstehen aus EINEM Fetch — WidgetKit ruft den
/// Provider nicht pro Entry auf. Die Views rechnen deshalb konsequent gegen `date`
/// (den Zeitpunkt, für den der Entry gerendert wird) und NIE gegen `Date()`.
struct TermineEntry: TimelineEntry {
    let date: Date
    /// Alle Feed-Einträge (aufsteigend nach Beginn), auch bereits vergangene.
    let items: [WidgetTermin]
    let counts: WidgetTerminCounts
    /// API-Key in der App-Group vorhanden (sonst: „In der App anmelden").
    let configured: Bool
    /// Es liegen überhaupt Daten vor (Netz ODER Cache).
    let loaded: Bool
    /// Daten stammen aus dem Offline-Cache.
    let fromCache: Bool
    /// Stand der Daten (für „Stand 14:20").
    let stamp: Date?
    var relevance: TimelineEntryRelevance?

    /// Noch nicht vorbei — das ist die Liste, die die Widgets zeigen.
    var visible: [WidgetTermin] { items.filter { !$0.isPast(at: date) } }

    /// Ganztägige Dauerläufer (Ferien, Reisen), die an einem früheren Tag begonnen haben.
    var ongoing: [WidgetTermin] { visible.filter { $0.isLongRunning(at: date) } }

    /// Echte, datierte Termine — alles außer den Dauerläufern.
    var scheduled: [WidgetTermin] { visible.filter { !$0.isLongRunning(at: date) } }

    /// Anzeige-Reihenfolge: Dauerläufer zählen ab heute, nicht ab ihrem Beginn.
    var ordered: [WidgetTermin] {
        visible.sorted { a, b in
            let ra = a.relevanceDate(at: date), rb = b.relevanceDate(at: date)
            return ra == rb ? a.startAt < b.startAt : ra < rb
        }
    }

    /// Der gerade laufende Termin (nur mit Uhrzeit; ganztägige gelten sonst den ganzen Tag als „läuft").
    var running: WidgetTermin? { scheduled.first { !$0.allDay && $0.isRunning(at: date) } }

    /// Reihenfolge für die Schlagzeile: nach Tag, INNERHALB eines Tages getimte Termine vor
    /// ganztägigen. Sonst verdrängt die Abfuhr (technisch 00:00) den Zahnarzt um 17:30 desselben
    /// Tages — in der Liste steht sie weiterhin oben, nur eben nicht als Schlagzeile.
    private var heroOrder: [WidgetTermin] {
        let cal = Calendar.current
        return scheduled.sorted { a, b in
            let da = cal.startOfDay(for: a.relevanceDate(at: date))
            let db = cal.startOfDay(for: b.relevanceDate(at: date))
            if da != db { return da < db }
            if a.allDay != b.allDay { return !a.allDay }
            return a.startAt < b.startAt
        }
    }

    /// Prominenter Termin: der laufende, sonst der nächste ECHTE Termin. Dauerläufer erst als
    /// letzter Ausweg — sonst stünde z.B. „Sommerferien 09.07.–30.07." drei Wochen lang als
    /// Schlagzeile im Widget und verdeckte den Termin, um den es eigentlich geht.
    var hero: WidgetTermin? { running ?? heroOrder.first ?? ongoing.first }

    /// Alles nach dem Hero (kompakte Liste in medium) — echte Termine zuerst, Dauerläufer danach.
    var following: [WidgetTermin] {
        guard let h = hero else { return [] }
        return (scheduled + ongoing).filter { $0.id != h.id }
    }
}

/// Ereignisgenaue Timeline: Entries genau an den Grenzen, an denen sich die Darstellung
/// ändert (Terminbeginn → „Läuft", Terminende → nächster Termin rückt vor, Mitternacht →
/// „Heute"/„Morgen"). Dazwischen rendert WidgetKit nichts neu — Countdowns laufen per
/// `Text(timerInterval:)` trotzdem live weiter.
struct TermineProvider: TimelineProvider {
    /// Obergrenze laut Spezifikation (WidgetKit-Budget).
    private let maxEntries = 40
    /// Grenzen weiter als 24 h in der Zukunft brauchen keinen eigenen Entry.
    private let horizonSeconds: TimeInterval = 24 * 3600
    /// Spätestens nach 30 Minuten frische Daten holen …
    private let maxRefresh: TimeInterval = 30 * 60
    /// … aber nie öfter als alle 5 Minuten (Budget schonen).
    private let minRefresh: TimeInterval = 5 * 60

    func placeholder(in context: Context) -> TermineEntry {
        Self.sampleEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (TermineEntry) -> Void) {
        // `context` bleibt außerhalb des Tasks (TimelineProviderContext ist nicht Sendable).
        if context.isPreview {
            completion(Self.sampleEntry())
            return
        }
        Task {
            let now = Date()
            let configured = SharedStore.apiKey?.isEmpty == false
            let result = await WidgetAPI.fetchTermine()
            completion(entry(at: now, result: result, configured: configured))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TermineEntry>) -> Void) {
        Task {
            let now = Date()
            let configured = SharedStore.apiKey?.isEmpty == false
            let result = await WidgetAPI.fetchTermine()
            let entries = buildEntries(at: now, result: result, configured: configured)
            completion(Timeline(entries: entries, policy: .after(refreshDate(after: now, entries: entries))))
        }
    }

    // ── Timeline-Bau ──

    /// Ein einzelner Entry für einen Zeitpunkt (Snapshot-Fall).
    private func entry(at date: Date, result: WidgetAPI.TermineResult?, configured: Bool) -> TermineEntry {
        let items = (result?.feed.items ?? []).sorted { $0.startAt < $1.startAt }
        return TermineEntry(date: date,
                            items: items,
                            counts: result?.feed.counts ?? WidgetTerminCounts(heute: 0, morgen: 0, woche: 0),
                            configured: configured,
                            loaded: result != nil,
                            fromCache: result?.fromCache ?? false,
                            stamp: result?.stamp,
                            relevance: Self.relevance(items: items, at: date))
    }

    /// Entries an jeder Termin-Grenze der nächsten ~24 h plus Mitternacht, gedeckelt.
    private func buildEntries(at now: Date, result: WidgetAPI.TermineResult?, configured: Bool) -> [TermineEntry] {
        let items = (result?.feed.items ?? []).sorted { $0.startAt < $1.startAt }
        let counts = result?.feed.counts ?? WidgetTerminCounts(heute: 0, morgen: 0, woche: 0)
        let horizon = now.addingTimeInterval(horizonSeconds)

        var marks: Set<Date> = [now]
        for t in items {
            for b in t.boundaries() where b > now && b <= horizon { marks.insert(b) }
        }
        // Tageswechsel: dort springt „Heute" auf „Morgen" und die Tagesgruppen rutschen.
        let cal = Calendar.current
        if let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)), midnight <= horizon {
            marks.insert(midnight)
        }

        return marks.sorted().prefix(maxEntries).map { d in
            TermineEntry(date: d,
                         items: items,
                         counts: counts,
                         configured: configured,
                         loaded: result != nil,
                         fromCache: result?.fromCache ?? false,
                         stamp: result?.stamp,
                         relevance: Self.relevance(items: items, at: d))
        }
    }

    /// Neue Daten holen: zur nächsten Grenze nach dem letzten Entry, spätestens nach 30 Min.
    private func refreshDate(after now: Date, entries: [TermineEntry]) -> Date {
        let cap = now.addingTimeInterval(maxRefresh)
        let next = entries.first(where: { $0.date > now })?.date ?? cap
        return max(min(next, cap), now.addingTimeInterval(minRefresh))
    }

    /// Smart Stack: je näher (bzw. je laufender) der nächste Termin, desto höher.
    /// Dauerläufer werden übersprungen — sonst gälte „Sommerferien" wochenlang als laufender Termin
    /// und das Widget stünde bis Oktober dauerhaft auf Höchstrelevanz (= Smart Stack unbrauchbar).
    private static func relevance(items: [WidgetTermin], at now: Date) -> TimelineEntryRelevance {
        guard let next = items.first(where: { !$0.isPast(at: now) && !$0.isLongRunning(at: now) }) else {
            return TimelineEntryRelevance(score: 0)
        }
        if next.isRunning(at: now) {
            let end = next.endDate ?? next.startDate.addingTimeInterval(3600)
            return TimelineEntryRelevance(score: 100, duration: max(0, end.timeIntervalSince(now)))
        }
        // 0 Min → 90, 15 h → 0 (linear abfallend).
        let minutes = max(0, next.startDate.timeIntervalSince(now) / 60)
        let score = max(0, 90 - minutes / 10)
        return TimelineEntryRelevance(score: Float(score), duration: 0)
    }

    // ── Platzhalter / Vorschau ──

    /// Beispieldaten für Platzhalter und Widget-Galerie (kein Netz).
    static func sampleEntry(at now: Date = Date()) -> TermineEntry {
        let items = [
            WidgetTermin(id: "termin-1", source: "termin", refId: 1,
                         title: "Zahnarzt Samu", subtitle: "Samu", location: "Praxis Dr. Ohle",
                         emoji: "🦷", color: "#3B82F6", date: "2026-07-24", time: "15:45",
                         startAt: now.addingTimeInterval(42 * 60).timeIntervalSince1970,
                         endAt: now.addingTimeInterval(102 * 60).timeIntervalSince1970,
                         allDay: false, daysUntil: 0, read: false, muted: false),
            WidgetTermin(id: "termin-2", source: "termin", refId: 2,
                         title: "Elternabend Kita", subtitle: "Elita", location: "Kita Sonnenschein",
                         emoji: "🏫", color: "#8B5CF6", date: "2026-07-24", time: "19:00",
                         startAt: now.addingTimeInterval(5 * 3600).timeIntervalSince1970,
                         endAt: nil, allDay: false, daysUntil: 0, read: true, muted: false),
            WidgetTermin(id: "abfuhr-3", source: "abfuhr", refId: 3,
                         title: "Restmüll rausstellen", subtitle: nil, location: nil,
                         emoji: "🗑️", color: "#64748B", date: "2026-07-25", time: nil,
                         startAt: now.addingTimeInterval(26 * 3600).timeIntervalSince1970,
                         endAt: nil, allDay: true, daysUntil: 1, read: false, muted: false)
        ]
        return TermineEntry(date: now,
                            items: items,
                            counts: WidgetTerminCounts(heute: 2, morgen: 1, woche: 5),
                            configured: true,
                            loaded: true,
                            fromCache: false,
                            stamp: now,
                            relevance: relevance(items: items, at: now))
    }
}
