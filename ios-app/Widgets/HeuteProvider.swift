import Foundation
import WidgetKit

/// Eintrag des Heute-Widgets. Additiv um den Termin-Feed erweitert — `snapshot` (Dashboard-Zähler)
/// bleibt unverändert, damit bestehende Platzierungen weiter funktionieren.
struct HeuteEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let configured: Bool
    /// Termin-Feed (`GET /api/v1/widget/termine`) — frisch oder aus dem App-Group-Cache; nil = nie geladen.
    var feed: WidgetTerminFeed? = nil
    /// true = `feed` kommt aus dem Cache (Netz nicht erreichbar) → Ansicht zeigt den Stand-Hinweis.
    var stale: Bool = false
    /// Zeitpunkt des letzten erfolgreichen Ladens (nur gesetzt, wenn `stale`).
    var cachedAt: Date? = nil
    var relevance: TimelineEntryRelevance? = nil
}

/// v1-Envelope des Widget-Feeds (`{ "data": {...}, "total": n }`).
private struct HeuteFeedEnvelope: Decodable {
    let data: WidgetTerminFeed
}

/// Lädt den Widget-Termin-Feed **defensiv**: frisch vom Backend, sonst der letzte Stand aus der
/// App-Group. Bewusst lokal in diesem File gehalten, damit der Heute-Provider unabhängig von
/// anderen Widget-Dateien kompiliert; das Ergebnis wird in denselben `WidgetCache` geschrieben,
/// den auch die App und die übrigen Widgets nutzen.
private enum HeuteTermineFeed {
    static func load(days: Int = 14) async -> (feed: WidgetTerminFeed?, stale: Bool) {
        if let req = SharedStore.request("/api/v1/widget/termine?days=\(days)"),
           let (data, resp) = try? await URLSession.shared.data(for: req),
           (resp as? HTTPURLResponse)?.statusCode == 200,
           let env = try? JSONDecoder().decode(HeuteFeedEnvelope.self, from: data) {
            WidgetCache.save(env.data)
            return (env.data, false)
        }
        return (WidgetCache.load(), true)
    }
}

/// Ereignisgenaue Timeline: je ein Entry an jeder Termin-Grenze der nächsten 24 h (Start/Ende)
/// plus Mitternacht — so springt das Widget exakt dann auf „Läuft“ bzw. auf den nächsten Termin,
/// ohne dafür Reload-Budget zu verbrauchen.
private enum HeuteTimeline {
    static func marks(now: Date, feed: WidgetTerminFeed?) -> [Date] {
        let cal = Calendar.current
        let horizon = now.addingTimeInterval(24 * 3600)
        var stamps = Set<TimeInterval>()

        for item in feed?.items ?? [] {
            for boundary in item.boundaries() {
                let d = boundary.addingTimeInterval(1) // 1 s nach der Grenze → Zustand ist sicher gewechselt
                if d > now, d <= horizon { stamps.insert(d.timeIntervalSince1970) }
            }
        }
        let midnight = cal.startOfDay(for: horizon).addingTimeInterval(2)
        if midnight > now, midnight <= horizon { stamps.insert(midnight.timeIntervalSince1970) }

        var dates = stamps.sorted().map { Date(timeIntervalSince1970: $0) }
        if dates.count > 23 { dates = Array(dates.prefix(23)) }
        return [now] + dates
    }

    /// Smart-Stack-Relevanz: je näher der nächste Termin, desto höher; laufender Termin = Maximum.
    static func relevance(at date: Date, feed: WidgetTerminFeed?) -> TimelineEntryRelevance {
        guard let next = (feed?.items ?? []).first(where: { !$0.isPast(at: date) }) else {
            return TimelineEntryRelevance(score: 0)
        }
        if next.isRunning(at: date) { return TimelineEntryRelevance(score: 100) }
        let minutes = next.startDate.timeIntervalSince(date) / 60
        return TimelineEntryRelevance(score: Float(max(0, 90 - min(minutes, 90))))
    }

    /// Nächster echter Reload: spätestens stündlich, jedenfalls zum Tageswechsel, frühestens in 15 min.
    static func refresh(now: Date) -> Date {
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(24 * 3600))
        let hourly = now.addingTimeInterval(3600)
        return max(min(hourly, midnight), now.addingTimeInterval(900))
    }
}

/// Beispieldaten für Platzhalter/Galerie (nie Netz).
private enum HeuteSample {
    static let snapshot = WidgetSnapshot(termineTitel: "Zahnarzt", termineDatum: "2026-07-24",
                                         remindersDue: 2, fotoInboxNeu: 3, mhdCount: 1,
                                         nextTripTitle: nil, nextTripDays: nil)

    static var feed: WidgetTerminFeed {
        let start = Date().addingTimeInterval(45 * 60)
        let zweiter = Date().addingTimeInterval(4 * 3600)
        let items = [
            WidgetTermin(id: "termin-1", source: "termin", refId: 1, title: "Zahnarzt",
                         subtitle: "Samu", location: "Praxis Dr. Meier", emoji: "🦷", color: "#3B82F6",
                         date: "2026-07-24", time: "15:45",
                         startAt: start.timeIntervalSince1970,
                         endAt: start.addingTimeInterval(3600).timeIntervalSince1970,
                         allDay: false, daysUntil: 0, read: false, muted: false),
            WidgetTermin(id: "termin-2", source: "termin", refId: 2, title: "Elternabend",
                         subtitle: "Elita", location: "Kita", emoji: "📅", color: "#22C55E",
                         date: "2026-07-24", time: "19:00",
                         startAt: zweiter.timeIntervalSince1970, endAt: nil,
                         allDay: false, daysUntil: 0, read: true, muted: false),
        ]
        return WidgetTerminFeed(now: Date().timeIntervalSince1970, owner: SharedStore.owner,
                                items: items,
                                counts: WidgetTerminCounts(heute: 2, morgen: 1, woche: 5))
    }
}

/// Lädt Dashboard-Snapshot und Termin-Feed parallel und baut daraus die ereignisgenaue Timeline.
struct HeuteProvider: TimelineProvider {
    func placeholder(in context: Context) -> HeuteEntry {
        HeuteEntry(date: Date(), snapshot: HeuteSample.snapshot, configured: true, feed: HeuteSample.feed)
    }

    func getSnapshot(in context: Context, completion: @escaping (HeuteEntry) -> Void) {
        // `context` NICHT in den Task hineinreichen (nicht Sendable) — nur den benötigten Bool.
        let isPreview = context.isPreview
        Task {
            let configured = SharedStore.apiKey?.isEmpty == false
            if isPreview {
                completion(HeuteEntry(date: Date(), snapshot: HeuteSample.snapshot,
                                      configured: true, feed: HeuteSample.feed))
                return
            }
            async let snapTask = WidgetAPI.fetch()
            async let feedTask = HeuteTermineFeed.load()
            let snap = await snapTask
            let (feed, stale) = await feedTask
            completion(HeuteEntry(date: Date(), snapshot: snap, configured: configured,
                                  feed: feed, stale: stale,
                                  cachedAt: stale ? WidgetCache.fetchedAt : nil))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HeuteEntry>) -> Void) {
        Task {
            let now = Date()
            let configured = SharedStore.apiKey?.isEmpty == false
            async let snapTask = WidgetAPI.fetch()
            async let feedTask = HeuteTermineFeed.load()
            let snap = await snapTask
            let (feed, stale) = await feedTask
            let cachedAt = stale ? WidgetCache.fetchedAt : nil

            let entries = HeuteTimeline.marks(now: now, feed: feed).map { d in
                HeuteEntry(date: d, snapshot: snap, configured: configured, feed: feed,
                           stale: stale, cachedAt: cachedAt,
                           relevance: HeuteTimeline.relevance(at: d, feed: feed))
            }
            completion(Timeline(entries: entries, policy: .after(HeuteTimeline.refresh(now: now))))
        }
    }
}
