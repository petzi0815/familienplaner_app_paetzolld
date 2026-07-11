import WidgetKit
import SwiftUI

/// Widget-eigene Farben (keine Abhängigkeit zum App-Theme).
private enum WT {
    static let start = Color(red: 0.00, green: 0.48, blue: 0.90)
    static let mid = Color(red: 0.35, green: 0.34, blue: 0.84)
    static let end = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let grad = LinearGradient(colors: [start, mid, end], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct HeuteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HeuteWidget", provider: HeuteProvider()) { entry in
            HeuteWidgetView(entry: entry)
                .containerBackground(for: .widget) { WT.grad.opacity(0.14) }
        }
        .configurationDisplayName("Heute")
        .description("Termine, Erinnerungen und neue Fotos auf einen Blick.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct HeuteWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HeuteEntry

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    private var snap: WidgetSnapshot? { entry.snapshot }

    // ── Home Screen ──
    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Heute", systemImage: "square.grid.2x2.fill")
                .font(.caption.weight(.bold)).foregroundStyle(WT.mid)
            if let s = snap {
                if let t = s.termineTitel {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t).font(.subheadline.weight(.semibold)).lineLimit(2)
                        if let d = s.termineDatum { Text(prettyDate(d)).font(.caption2).foregroundStyle(.secondary) }
                    }
                } else {
                    Text("Keine Termine").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    pill("\(s.fotoInboxNeu)", "photo", WT.start)
                    pill("\(s.remindersDue)", "bell", WT.end)
                }
            } else {
                Text(entry.configured ? "Keine Verbindung" : "In der App anmelden")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Heute", systemImage: "square.grid.2x2.fill")
                    .font(.caption.weight(.bold)).foregroundStyle(WT.mid)
                if let t = snap?.termineTitel {
                    Text(t).font(.headline).lineLimit(2)
                    if let d = snap?.termineDatum { Text(prettyDate(d)).font(.caption).foregroundStyle(.secondary) }
                } else {
                    Text("Keine anstehenden Termine").font(.subheadline).foregroundStyle(.secondary)
                }
                if let trip = snap?.nextTripTitle, let days = snap?.nextTripDays {
                    Label("\(trip) · in \(max(days,0)) T.", systemImage: "airplane").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                stat("photo.fill", "\(snap?.fotoInboxNeu ?? 0)", "Fotos", WT.start)
                stat("bell.badge.fill", "\(snap?.remindersDue ?? 0)", "Erinnerungen", WT.mid)
                stat("clock.badge.exclamationmark", "\(snap?.mhdCount ?? 0)", "MHD bald", WT.end)
            }
            .frame(width: 120, alignment: .leading)
        }
    }

    // ── Lock Screen / StandBy ──
    private var inline: some View {
        Label("\(snap?.fotoInboxNeu ?? 0) Fotos · \(snap?.remindersDue ?? 0) Erinnerungen", systemImage: "square.grid.2x2")
    }

    private var circular: some View {
        Gauge(value: Double(min(snap?.fotoInboxNeu ?? 0, 9)), in: 0...9) {
            Image(systemName: "photo")
        } currentValueLabel: {
            Text("\(snap?.fotoInboxNeu ?? 0)")
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Heute", systemImage: "square.grid.2x2.fill").font(.caption2.weight(.bold))
            if let t = snap?.termineTitel {
                Text(t).font(.caption.weight(.semibold)).lineLimit(1)
            } else {
                Text("Keine Termine").font(.caption)
            }
            Text("\(snap?.fotoInboxNeu ?? 0) Fotos · \(snap?.remindersDue ?? 0) Erinnerungen")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // ── Bausteine ──
    private func pill(_ value: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(value).font(.caption.weight(.bold))
        }
        .foregroundStyle(color)
    }

    private func stat(_ icon: String, _ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.footnote).foregroundStyle(color).frame(width: 18)
            Text(value).font(.subheadline.weight(.bold))
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func prettyDate(_ s: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "de_DE")
        guard let d = f.date(from: String(s.prefix(10))) else { return s }
        let out = DateFormatter(); out.locale = Locale(identifier: "de_DE"); out.setLocalizedDateFormatFromTemplate("EdMMM")
        return out.string(from: d)
    }
}
