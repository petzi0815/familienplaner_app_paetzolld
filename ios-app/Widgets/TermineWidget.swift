import WidgetKit
import SwiftUI

/// Termin-Widget — der wichtigste Inhalt der App auf Home- und Sperrbildschirm.
///
/// Alle Größen rendern gegen `entry.date` (siehe `TermineProvider`): dadurch springt die
/// Darstellung ereignisgenau auf „Läuft" bzw. auf den nächsten Termin. Countdowns nutzen
/// `Text(timerInterval:)` und laufen ohne Timeline-Reload weiter.
struct TermineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TermineWidget", provider: TermineProvider()) { entry in
            TermineWidgetView(entry: entry)
                .containerBackground(for: .widget) { WTheme.grad.opacity(0.14) }
        }
        .configurationDisplayName("Termine")
        .description("Der nächste bzw. gerade laufende Termin und was danach kommt.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

/// Eine Tagesgruppe der großen Ansicht (`id` = Überschrift, z. B. „Heute").
/// Bewusst ein Typ statt eines Tupels — Swift kennt keine Key-Paths auf Tupel-Elemente.
private struct WDayGroup: Identifiable {
    let id: String
    var items: [WidgetTermin]
}

// MARK: - Ansicht

struct TermineWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TermineEntry

    var body: some View {
        content.widgetURL(rootURL)
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        case .systemLarge: large
        default: small
        }
    }

    // MARK: Home Screen

    @ViewBuilder private var small: some View {
        if let h = entry.hero {
            VStack(alignment: .leading, spacing: 3) {
                hero(h, big: false)
                footer
            }
        } else {
            emptyState
        }
    }

    @ViewBuilder private var medium: some View {
        if let h = entry.hero {
            HStack(alignment: .top, spacing: 12) {
                Link(destination: deepLink(h)) {
                    hero(h, big: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                VStack(alignment: .leading, spacing: 7) {
                    Text("Danach")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WTheme.mid)
                    if entry.following.isEmpty {
                        Text("Nichts weiter geplant")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        ForEach(entry.following.prefix(3)) { t in
                            Link(destination: deepLink(t)) { row(t, compact: true) }
                        }
                    }
                    Spacer(minLength: 0)
                    footer
                }
                .frame(width: 148, alignment: .leading)
            }
        } else {
            emptyState
        }
    }

    @ViewBuilder private var large: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Label("Termine", systemImage: "calendar")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WTheme.mid)
                Spacer(minLength: 0)
                Text("Heute \(entry.counts.heute) · Woche \(entry.counts.woche)")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if entry.visible.isEmpty {
                emptyState
                Spacer(minLength: 0)
            } else {
                ForEach(dayGroups) { group in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(group.id)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        ForEach(group.items) { t in
                            Link(destination: deepLink(t)) { row(t) }
                        }
                    }
                }
                Spacer(minLength: 0)
                footer
            }
        }
    }

    // MARK: Sperrbildschirm (monochrom-tauglich, kein Farbverlass)

    @ViewBuilder private var rectangular: some View {
        if let h = entry.hero {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: h.allDay ? "sun.max"
                                               : (isRunning(h) ? "record.circle" : "clock"))
                        .font(.caption2)
                    Text(h.allDay ? "Ganztägig" : WDate.time(h.startDate))
                        .font(.caption.weight(.bold).monospacedDigit())
                    WCountdown(termin: h, now: entry.date)
                        .font(.caption2.monospacedDigit())
                }
                .widgetAccentable()

                Text(h.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Text(secondaryLine(after: h))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Label("Termine", systemImage: "calendar")
                    .font(.caption2.weight(.bold))
                    .widgetAccentable()
                Text(emptyTitle).font(.caption.weight(.semibold)).lineLimit(1)
                Text(emptySubtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    @ViewBuilder private var inline: some View {
        if let h = entry.hero {
            Text(inlineText(h))
        } else {
            Text(emptyTitle)
        }
    }

    @ViewBuilder private var circular: some View {
        if let h = entry.hero, !h.allDay, gaugeSeconds(h) != nil {
            Gauge(value: gaugeProgress(h), in: 0...1) {
                Image(systemName: "calendar")
            } currentValueLabel: {
                Text(shortRemaining(h)).minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            Gauge(value: Double(min(entry.counts.heute, 9)), in: 0...9) {
                Image(systemName: "calendar")
            } currentValueLabel: {
                Text("\(entry.counts.heute)")
            }
            .gaugeStyle(.accessoryCircular)
        }
    }

    // MARK: Bausteine

    /// Prominenter Termin: Uhrzeit groß, Titel, Ort/Person, Live-Countdown.
    @ViewBuilder private func hero(_ t: WidgetTermin, big: Bool) -> some View {
        VStack(alignment: .leading, spacing: big ? 3 : 2) {
            HStack(spacing: 5) {
                Text(t.emoji).font(.footnote)
                WDot(color: WTheme.color(hex: t.color), size: 7)
                Spacer(minLength: 0)
                if isRunning(t) { WRunningBadge() }
            }

            Text(t.allDay ? "Ganztägig" : WDate.time(t.startDate))
                .font(.system(size: big ? 30 : 27, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(isRunning(t) ? WTheme.running : Color.primary)

            Text(t.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            if let d = detail(t) {
                Label(d.text, systemImage: d.icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Image(systemName: isRunning(t) ? "hourglass" : "arrow.right.circle")
                    .font(.caption2)
                WCountdown(termin: t, now: entry.date)
            }
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(isRunning(t) ? WTheme.running : WTheme.soon)
        }
    }

    /// Kompakte Listenzeile: Uhrzeit-Spalte · Kategorie-Punkt · Titel/Ort · „Läuft".
    @ViewBuilder private func row(_ t: WidgetTermin, compact: Bool = false) -> some View {
        HStack(spacing: 7) {
            Text(t.allDay ? "ganzt." : WDate.time(t.startDate))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(isRunning(t) ? WTheme.running : Color.primary)
                .frame(width: compact ? 40 : 44, alignment: .leading)

            WDot(color: WTheme.color(hex: t.color), size: isRunning(t) ? 8 : 6)

            VStack(alignment: .leading, spacing: 0) {
                Text(t.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if !compact, let d = detail(t) {
                    Text(d.text)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if isRunning(t) {
                WRunningBadge()
            } else if t.isLongRunning(at: entry.date) {
                // Dauerläufer: der Start liegt hinter uns, „jetzt" wäre irreführend.
                Text(t.endDate.map { "bis \(WDate.shortDate($0))" } ?? "läuft")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if !compact {
                Text(WDate.relative(to: t.startDate, now: entry.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        // Bereits gelesene Termine treten optisch zurück.
        .opacity(t.read ? 0.6 : 1)
    }

    /// Fußzeile: Offline-Stand bzw. Tageszähler.
    @ViewBuilder private var footer: some View {
        if entry.fromCache, let s = entry.stamp {
            Label(WDate.stamp(s), systemImage: "wifi.slash")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if family != .systemSmall {
            Text("Heute \(entry.counts.heute) · Morgen \(entry.counts.morgen)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// Leerzustand — unterscheidet „nicht angemeldet", „keine Verbindung" und „nichts geplant".
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: emptyIcon)
                .font(.title3)
                .foregroundStyle(WTheme.mid)
            Text(emptyTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(emptySubtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Ableitungen

    private func isRunning(_ t: WidgetTermin) -> Bool {
        !t.allDay && t.isRunning(at: entry.date)
    }

    /// Zweitwichtigste Zeile: Ort, sonst Person/Kategorie.
    private func detail(_ t: WidgetTermin) -> (text: String, icon: String)? {
        if let l = t.location, !l.isEmpty { return (l, "mappin.and.ellipse") }
        if let s = t.subtitle, !s.isEmpty { return (s, "person.fill") }
        return nil
    }

    /// Sperrbildschirm-Zeile 3: Ort, sonst der Termin danach, sonst der Tageszähler.
    private func secondaryLine(after t: WidgetTermin) -> String {
        if let d = detail(t) { return d.text }
        if let next = entry.following.first {
            return "danach \(next.allDay ? "ganztägig" : WDate.time(next.startDate)) \(next.title)"
        }
        return entry.counts.heute > 0 ? "\(entry.counts.heute) Termine heute" : "Nichts weiter geplant"
    }

    private func inlineText(_ t: WidgetTermin) -> String {
        let zeit = t.allDay ? "Ganztägig" : WDate.time(t.startDate)
        return "\(t.emoji) \(zeit) \(t.title)"
    }

    /// Tagesgruppen für die große Ansicht („Heute", „Morgen", „Mi, 29. Jul").
    private var dayGroups: [WDayGroup] {
        var out: [WDayGroup] = []
        // `ordered` statt `visible` und Gruppierung nach `relevanceDate`: laufende Dauerläufer
        // (Ferien/Reisen) gehören unter „Heute", nicht unter ihren Starttag vor drei Wochen.
        for t in entry.ordered.prefix(8) {
            let header = WDate.dayHeader(t.relevanceDate(at: entry.date), now: entry.date)
            if let idx = out.firstIndex(where: { $0.id == header }) {
                out[idx].items.append(t)
            } else {
                out.append(WDayGroup(id: header, items: [t]))
            }
        }
        return out
    }

    // MARK: Gauge (accessoryCircular)

    /// Restsekunden bis zum Start — nil, wenn zu weit weg oder schon begonnen.
    private func gaugeSeconds(_ t: WidgetTermin) -> Double? {
        let s = t.startDate.timeIntervalSince(entry.date)
        guard s > 0, s <= 12 * 3600 else { return nil }
        return s
    }

    /// Füllt sich, je näher der Termin rückt (12 h → 0, Start → 1).
    private func gaugeProgress(_ t: WidgetTermin) -> Double {
        guard let s = gaugeSeconds(t) else { return 0 }
        return max(0, min(1, 1 - s / (12 * 3600)))
    }

    /// Sehr kurze Restzeit für den engen Kreis: „42m" / „6h".
    private func shortRemaining(_ t: WidgetTermin) -> String {
        guard let s = gaugeSeconds(t) else { return "\(entry.counts.heute)" }
        let mins = Int(s / 60)
        return mins < 60 ? "\(mins)m" : "\(mins / 60)h"
    }

    // MARK: Leerzustands-Texte

    private var emptyIcon: String {
        if !entry.configured { return "person.crop.circle.badge.questionmark" }
        if !entry.loaded { return "wifi.slash" }
        return "calendar.badge.checkmark"
    }

    private var emptyTitle: String {
        if !entry.configured { return "In der App anmelden" }
        if !entry.loaded { return "Keine Verbindung" }
        return "Keine Termine"
    }

    private var emptySubtitle: String {
        if !entry.configured { return "Adresse und Schlüssel fehlen" }
        if !entry.loaded {
            if let s = entry.stamp { return WDate.stamp(s) }
            return "Später erneut versuchen"
        }
        return "Die nächsten Tage sind frei"
    }

    // MARK: Deep-Links

    private static let heuteURL = URL(string: "familienplaner://heute") ?? URL(fileURLWithPath: "/")
    private static let termineURL = URL(string: "familienplaner://termine") ?? URL(fileURLWithPath: "/")

    /// Ziel beim Tippen: der Termin selbst, sonst die Tagesübersicht.
    private func deepLink(_ t: WidgetTermin) -> URL {
        if t.source == "termin", let u = URL(string: "familienplaner://termin/\(t.refId)") { return u }
        return Self.heuteURL
    }

    /// Ganzflächiges Ziel: kleine/Sperrbildschirm-Größen springen direkt in den Termin,
    /// medium/large haben je Zeile eigene `Link`s und öffnen sonst die Terminliste.
    private var rootURL: URL {
        switch family {
        case .systemMedium, .systemLarge: return Self.termineURL
        default: return entry.hero.map { deepLink($0) } ?? Self.heuteURL
        }
    }
}

// MARK: - Live-Countdown

/// Countdown ohne Timeline-Reload: läuft der Termin, zählt die Restzeit; steht er kurz bevor,
/// zählt die Zeit bis zum Start; sonst eine kompakte relative Angabe („in 3 Std").
struct WCountdown: View {
    let termin: WidgetTermin
    let now: Date

    private var end: Date { termin.endDate ?? termin.startDate.addingTimeInterval(3600) }
    private var startsSoon: Bool {
        termin.startDate > now && termin.startDate.timeIntervalSince(now) < 3600
    }

    var body: some View {
        if termin.isLongRunning(at: now) {
            // Dauerläufer (Ferien/Reise): der Beginn liegt in der Vergangenheit — ein Countdown
            // darauf wäre sinnlos („Do, 9. Jul"), interessant ist, wie lange er noch läuft.
            Text(termin.endDate.map { "noch bis \(WDate.shortDate($0))" } ?? "läuft")
        } else if termin.allDay {
            // Ganztägig: kein Countdown, sondern der Tag selbst („Heute" / „Mi, 29. Jul").
            Text(WDate.dayHeader(termin.startDate, now: now))
        } else if termin.isRunning(at: now), end > now {
            Text(timerInterval: now...end, countsDown: true)
        } else if startsSoon {
            Text(timerInterval: now...termin.startDate, countsDown: true)
        } else if termin.startDate > now {
            Text(WDate.relative(to: termin.startDate, now: now))
        } else {
            Text("gerade eben")
        }
    }
}
