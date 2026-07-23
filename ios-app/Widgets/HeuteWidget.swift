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
        .description("Nächste Termine links, was heute ganztägig läuft rechts.")
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
    /// Schlagzeile der einspaltigen Ansichten (klein, Sperrbildschirm): ein Termin MIT UHRZEIT
    /// heute schlägt alles; danach was heute ganztägig läuft; erst dann der nächste Termin
    /// überhaupt. Sonst stünde „Ganztägig · Gelbe Tonne" über einem Arzttermin am selben Tag.
    private var focus: WidgetTermin? {
        let heuteGetimt = timed.filter { Calendar.current.isDate($0.startDate, inSameDayAs: now) }
        return heuteGetimt.first { $0.isRunning(at: now) }
            ?? heuteGetimt.first
            ?? allDayActive.first
            ?? timed.first
            ?? upcoming.first
    }
    private var followers: [WidgetTermin] { upcoming.filter { $0.id != focus?.id } }
    private var offline: Bool { snap == nil && entry.feed == nil }

    // ── Zweispaltige Aufteilung (systemMedium): links Termine mit Uhrzeit, rechts ganztägig ──
    /// Termine mit Uhrzeit — auch an kommenden Tagen, damit die linke Spalte nicht leer bleibt,
    /// wenn heute nichts Getimtes ansteht.
    private var timed: [WidgetTermin] { upcoming.filter { !$0.allDay } }
    /// Ganztägige Einträge, die JETZT aktiv sind (inkl. mehrtägiger Ferien/Reisen).
    private var allDayActive: [WidgetTermin] { upcoming.filter { $0.allDay && $0.isRunning(at: now) } }
    /// Ganztägige, die erst noch kommen — füllen die rechte Spalte auf, mit Tagesangabe.
    private var allDayNext: [WidgetTermin] { upcoming.filter { $0.allDay && !$0.isRunning(at: now) } }
    private var allDayShown: [WidgetTermin] { Array((allDayActive + allDayNext).prefix(3)) }
    /// Kopf der linken Spalte: der laufende getimte Termin, sonst der nächste.
    private var timedFocus: WidgetTermin? { timed.first { $0.isRunning(at: now) } ?? timed.first }

    // ── Home Screen ──
    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            statusOrTermin
            Spacer(minLength: 0)
            allDayChip
            stampLine
        }
    }

    /// Zweispaltig: links die Termine mit Uhrzeit (auch kommende), rechts was ganztägig läuft.
    private var medium: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                header
                terminColumn
                Spacer(minLength: 0)
                stampLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            allDayColumn
                .frame(width: 118, alignment: .leading)
        }
    }

    /// Linke Spalte: der wichtigste Termin mit Uhrzeit + die nächsten beiden.
    @ViewBuilder private var terminColumn: some View {
        if !entry.configured {
            Text("In der App anmelden").font(.caption).foregroundStyle(.secondary)
        } else if let t = timedFocus {
            // Nur EINE Folgezeile: in systemMedium bleiben nach Kopfzeile und Hero rund 20 pt —
            // zwei Zeilen haben den Hero gestaucht und den Ort abgeschnitten.
            terminHero(t, titleLines: 1)
            if let next = timed.first(where: { $0.id != t.id }) { row(next) }
        } else if let titel = snap?.termineTitel {
            // Termin-Feed fehlt, aber der Dashboard-Snapshot kennt einen Termin — dann NICHT
            // „keine Termine" behaupten (der Feed-Fehler ist kein leerer Kalender).
            VStack(alignment: .leading, spacing: 1) {
                Text(titel).font(.subheadline.weight(.semibold)).lineLimit(2)
                if let d = snap?.termineDatum {
                    Text(prettyDate(d)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        } else {
            Text(offline ? "Keine Verbindung" : "Keine Termine mit Uhrzeit")
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    /// Rechte Spalte: ganztägige Einträge — laufende zuerst, danach die nächsten.
    @ViewBuilder private var allDayColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Ganztägig", systemImage: "sun.max.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(WTheme.end)
                .lineLimit(1)
            if allDayShown.isEmpty {
                Text("Nichts").font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(allDayShown) { t in allDayRow(t) }
            }
            Spacer(minLength: 0)
        }
    }

    private func allDayRow(_ t: WidgetTermin) -> some View {
        HStack(alignment: .top, spacing: 5) {
            WDot(color: WTheme.color(hex: t.color), size: 6).padding(.top, 4)
            VStack(alignment: .leading, spacing: 0) {
                Text(t.title).font(.caption2.weight(.medium)).lineLimit(1)
                if let hint = allDayHint(t) {
                    Text(hint).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(t.read ? 0.65 : 1)
    }

    /// Zusatz unter dem Titel: bei Dauerläufern das Ende, bei künftigen der Tag; heute aktive
    /// brauchen keinen — sie stehen ohnehin unter „Ganztägig".
    private func allDayHint(_ t: WidgetTermin) -> String? {
        if t.isLongRunning(at: now) { return t.endDate.map { "bis \(WDate.shortDate($0))" } }
        if !t.isRunning(at: now) { return WDate.dayHeader(t.startDate, now: now) }
        return nil
    }

    /// Kompakter Ganztägig-Hinweis für die kleine Ansicht (dort ist keine zweite Spalte drin).
    @ViewBuilder private var allDayChip: some View {
        // Ohne den Ausschluss stuende derselbe Eintrag zweimal untereinander, sobald der Hero
        // mangels getimtem Termin selbst auf den ganztägigen zurückfällt.
        let rest = allDayActive.filter { $0.id != focus?.id }
        if let t = rest.first {
            HStack(spacing: 4) {
                WDot(color: WTheme.color(hex: t.color), size: 6)
                Text(t.title).font(.caption2).lineLimit(1)
                if rest.count > 1 {
                    Text("+\(rest.count - 1)")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
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
    private func terminHero(_ t: WidgetTermin, titleLines: Int = 2) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                WDot(color: WTheme.color(hex: t.color))
                // Wochentag mit in die grosse Zeile, wenn der Termin nicht heute ist — „14:30"
                // allein liest sich sonst wie „gleich", auch wenn er neun Tage entfernt ist.
                Text(heroTime(t))
                    .font(.title3.weight(.bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if t.isRunning(at: now) { WRunningBadge() }
                Spacer(minLength: 0)
            }
            countdown(for: t)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(t.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(titleLines)
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

    /// Kompakte Folgezeile für die nächsten Termine. Termine an einem anderen Tag bekommen den
    /// Wochentag davor („Fr 15:30"), sonst wäre eine Uhrzeit ohne Datum irreführend.
    private func row(_ t: WidgetTermin) -> some View {
        HStack(spacing: 5) {
            WDot(color: WTheme.color(hex: t.color), size: 6)
            Text(rowTime(t))
                .font(.caption2.weight(.semibold))
                .fixedSize()
            Text(t.title).font(.caption2).lineLimit(1)
            Spacer(minLength: 0)
        }
        .opacity(t.read ? 0.6 : 1)
    }

    /// Grosse Zeile des Hero: „15:45" heute, sonst „Fr 15:45"; ganztägig ohne Uhrzeit.
    private func heroTime(_ t: WidgetTermin) -> String {
        if t.allDay { return "Ganztägig" }
        let zeit = WDate.time(t.startDate)
        guard !Calendar.current.isDate(t.startDate, inSameDayAs: now) else { return zeit }
        return "\(WDate.weekday(t.startDate)) \(zeit)"
    }

    private func rowTime(_ t: WidgetTermin) -> String {
        if t.allDay { return "ganztg." }
        let zeit = WDate.time(t.startDate)
        guard !Calendar.current.isDate(t.startDate, inSameDayAs: now) else { return zeit }
        return "\(WDate.weekday(t.startDate)) \(zeit)"
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

    private func prettyDate(_ s: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "de_DE")
        guard let d = f.date(from: String(s.prefix(10))) else { return s }
        let out = DateFormatter(); out.locale = Locale(identifier: "de_DE"); out.setLocalizedDateFormatFromTemplate("EdMMM")
        return out.string(from: d)
    }
}
