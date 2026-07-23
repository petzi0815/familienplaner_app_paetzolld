import WidgetKit
import SwiftUI

/// „Heute“ — Termin im Fokus (Uhrzeit, Countdown, Läuft-Badge, Ort) plus die Tages-Zähler.
/// `kind` bleibt „HeuteWidget“, damit bestehende Platzierungen erhalten bleiben.
struct HeuteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HeuteWidget", provider: HeuteProvider()) { entry in
            HeuteWidgetView(entry: entry)
                .containerBackground(for: .widget) { WTheme.grad.opacity(0.14) }
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
        content.widgetURL(URL(string: "familienplaner://heute"))
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    // ── Ableitungen ──
    private var snap: WidgetSnapshot? { entry.snapshot }
    /// Bezugszeitpunkt = Entry-Zeit (die Timeline liefert Entries an jeder Termin-Grenze).
    private var now: Date { entry.date }
    private var upcoming: [WidgetTermin] { (entry.feed?.items ?? []).filter { !$0.isPast(at: now) } }
    /// Ganztägige Dauerläufer (Ferien/Reisen), die an einem früheren Tag begonnen haben — sie sind
    /// Hintergrund-Information und dürfen die Schlagzeile nicht belegen.
    private var scheduled: [WidgetTermin] { upcoming.filter { !$0.isLongRunning(at: now) } }
    /// Der gerade laufende Termin hat Vorrang, sonst der nächste ECHTE Termin; Dauerläufer zuletzt.
    private var focus: WidgetTermin? {
        scheduled.first { $0.isRunning(at: now) } ?? scheduled.first ?? upcoming.first
    }
    private var followers: [WidgetTermin] { upcoming.filter { $0.id != focus?.id } }
    private var offline: Bool { snap == nil && entry.feed == nil }

    // ── Home Screen ──
    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            statusOrTermin
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                pill("\(snap?.fotoInboxNeu ?? 0)", "photo", WTheme.start)
                pill("\(snap?.remindersDue ?? 0)", "bell", WTheme.end)
                Spacer(minLength: 0)
            }
            stampLine
        }
    }

    private var medium: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                header
                statusOrTermin
                if !followers.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(followers.prefix(3))) { t in row(t) }
                    }
                }
                Spacer(minLength: 0)
                stampLine
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                stat("photo.fill", "\(snap?.fotoInboxNeu ?? 0)", "Fotos", WTheme.start)
                stat("bell.badge.fill", "\(snap?.remindersDue ?? 0)", "Erinnerungen", WTheme.mid)
                stat("clock.badge.exclamationmark", "\(snap?.mhdCount ?? 0)", "MHD bald", WTheme.end)
            }
            .frame(width: 118, alignment: .leading)
        }
    }

    // ── Lock Screen / StandBy ──
    @ViewBuilder private var inline: some View {
        if let t = focus {
            Text(verbatim: inlineTitle(t))
        } else {
            Label("\(snap?.fotoInboxNeu ?? 0) Fotos · \(snap?.remindersDue ?? 0) Erinnerungen",
                  systemImage: "square.grid.2x2")
        }
    }

    private var circular: some View {
        Gauge(value: Double(min(snap?.fotoInboxNeu ?? 0, 9)), in: 0...9) {
            Image(systemName: "photo")
        } currentValueLabel: {
            Text("\(snap?.fotoInboxNeu ?? 0)")
        }
        .gaugeStyle(.accessoryCircular)
    }

    @ViewBuilder private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let t = focus {
                HStack(spacing: 5) {
                    Text(t.allDay ? "Ganztägig" : WDate.time(t.startDate))
                        .font(.headline)
                        .fixedSize()
                    countdown(for: t).font(.caption2)
                }
                .widgetAccentable()
                Text(t.title).font(.caption.weight(.semibold)).lineLimit(1)
                if let loc = t.location, !loc.isEmpty {
                    Text(loc).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                } else if let n = followers.first {
                    Text(verbatim: nextHint(n))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Label("Heute", systemImage: "square.grid.2x2.fill")
                    .font(.caption2.weight(.bold))
                    .widgetAccentable()
                Text(emptyHint).font(.caption).lineLimit(1)
                Text("\(snap?.fotoInboxNeu ?? 0) Fotos · \(snap?.remindersDue ?? 0) Erinnerungen")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // ── Bausteine ──
    private var header: some View {
        Label("Heute", systemImage: "square.grid.2x2.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(WTheme.mid)
    }

    /// Termin-Fokus bzw. sauberer Leer-/Fehlerzustand.
    @ViewBuilder private var statusOrTermin: some View {
        if !entry.configured {
            Text("In der App anmelden").font(.caption).foregroundStyle(.secondary)
        } else if let t = focus {
            terminHero(t)
        } else if let titel = snap?.termineTitel {
            // Fallback auf den Dashboard-Snapshot, falls der Termin-Feed (noch) fehlt.
            VStack(alignment: .leading, spacing: 1) {
                Text(titel).font(.subheadline.weight(.semibold)).lineLimit(2)
                if let d = snap?.termineDatum {
                    Text(prettyDate(d)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        } else {
            Text(emptyHint).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var emptyHint: String {
        if !entry.configured { return "In der App anmelden" }
        return offline ? "Keine Verbindung" : "Keine Termine"
    }

    /// Der wichtigste Termin: Uhrzeit groß, Läuft-Badge, Countdown, Titel, Ort.
    private func terminHero(_ t: WidgetTermin) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                WDot(color: WTheme.color(hex: t.color))
                Text(t.allDay ? "Ganztägig" : WDate.time(t.startDate))
                    .font(.title3.weight(.bold))
                    .fixedSize()
                if t.isRunning(at: now) { WRunningBadge() }
                Spacer(minLength: 0)
            }
            countdown(for: t)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(t.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            if let loc = t.location, !loc.isEmpty {
                Label(loc, systemImage: "mappin.and.ellipse")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else if let sub = t.subtitle, !sub.isEmpty {
                Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .opacity(t.read && !t.isRunning(at: now) ? 0.75 : 1)
    }

    /// Live-Countdown (WidgetKit rendert `.relative` ohne zusätzlichen Timeline-Reload).
    private func countdown(for t: WidgetTermin) -> Text {
        if t.isRunning(at: now) {
            if let e = t.endDate, e > now { return Text("noch ") + Text(e, style: .relative) }
            return Text("läuft gerade")
        }
        if t.allDay || !Calendar.current.isDate(t.startDate, inSameDayAs: now) {
            return Text(WDate.dayHeader(t.startDate, now: now))
        }
        return Text("in ") + Text(t.startDate, style: .relative)
    }

    /// Kompakte Folgezeile für die nächsten Termine.
    private func row(_ t: WidgetTermin) -> some View {
        HStack(spacing: 5) {
            WDot(color: WTheme.color(hex: t.color), size: 6)
            Text(t.allDay ? "ganztg." : WDate.time(t.startDate))
                .font(.caption2.weight(.semibold))
                .fixedSize()
            Text(t.title).font(.caption2).lineLimit(1)
            Spacer(minLength: 0)
        }
        .opacity(t.read ? 0.6 : 1)
    }

    /// Offline-Hinweis mit dem Zeitpunkt des letzten erfolgreichen Ladens.
    @ViewBuilder private var stampLine: some View {
        if entry.stale, let at = entry.cachedAt {
            Text(WDate.stamp(at)).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
    }

    private func inlineTitle(_ t: WidgetTermin) -> String {
        let zeit = t.allDay ? "" : WDate.time(t.startDate) + " "
        return "\(t.emoji) \(zeit)\(t.title)"
    }

    /// Zeile 3 auf dem Sperrbildschirm, wenn der Fokus-Termin keinen Ort hat.
    private func nextHint(_ t: WidgetTermin) -> String {
        let zeit = t.allDay ? "ganztägig" : WDate.time(t.startDate)
        return "Danach \(zeit) · \(t.title)"
    }

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
