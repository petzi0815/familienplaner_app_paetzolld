import Foundation
import WidgetKit

struct HeuteEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let configured: Bool
}

/// Aktualisiert die Widgets stündlich (Push-Reload zusätzlich bei Login/Logout via WidgetCenter).
struct HeuteProvider: TimelineProvider {
    func placeholder(in context: Context) -> HeuteEntry {
        HeuteEntry(date: Date(), snapshot: WidgetSnapshot(termineTitel: "Zahnarzt", termineDatum: "2026-07-12", remindersDue: 2, fotoInboxNeu: 3, mhdCount: 1, nextTripTitle: nil, nextTripDays: nil), configured: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (HeuteEntry) -> Void) {
        Task {
            let configured = SharedStore.apiKey?.isEmpty == false
            completion(HeuteEntry(date: Date(), snapshot: await WidgetAPI.fetch(), configured: configured))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HeuteEntry>) -> Void) {
        Task {
            let configured = SharedStore.apiKey?.isEmpty == false
            let snap = await WidgetAPI.fetch()
            let refresh = Calendar.current.date(byAdding: .minute, value: 60, to: Date()) ?? Date().addingTimeInterval(3600)
            let entry = HeuteEntry(date: Date(), snapshot: snap, configured: configured)
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }
}
