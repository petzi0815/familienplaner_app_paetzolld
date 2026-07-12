import SwiftUI
import UIKit

/// „Heute" — kompakter Tageszustand aus GET /api/v1/dashboard/today.
struct HeuteView: View {
    @EnvironmentObject private var app: AppState
    @State private var calMessage = ""

    private let statCols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let d = app.dashboard {
                    VStack(spacing: 20) {
                        stats(d)
                        if let ab = d.abfuhrNext, !ab.isEmpty { abfuhr(ab) }
                        if !d.termineUpcoming.isEmpty { termine(d.termineUpcoming) }
                        if let trip = d.nextTrip { reise(trip) }
                        if !d.vorratBaldAblaufend.isEmpty { vorrat(d.vorratBaldAblaufend) }
                    }
                    .padding()
                } else if let err = app.dashboardError {
                    ContentUnavailableView {
                        Label("Keine Verbindung", systemImage: "wifi.slash")
                    } description: { Text(err) } actions: {
                        Button("Erneut laden") { Task { await app.loadDashboard() } }
                            .buttonStyle(.glassProminent)
                    }
                    .padding(.top, 60)
                } else {
                    ProgressView("Lädt …").padding(.top, 80)
                }
            }
            .background(Palette.gradient(for: "termine").opacity(0.06).ignoresSafeArea())
            .navigationTitle(greeting)
            .refreshable { await app.loadDashboard() }
            .task { if app.dashboard == nil { await app.loadDashboard() } }
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h { case 5..<11: return "Guten Morgen"; case 11..<17: return "Hallo"; case 17..<22: return "Guten Abend"; default: return "Gute Nacht" }
    }

    // ── Bunte Kennzahl-Kacheln ──
    private func stats(_ d: DashboardToday) -> some View {
        LazyVGrid(columns: statCols, spacing: 12) {
            StatTile(icon: "tray.full.fill", key: "foto", value: d.counts.fotoInboxNeu, label: "Neue Fotos")
                .onTapGesture { app.selectedTab = .inbox }
            StatTile(icon: "bell.badge.fill", key: "termine", value: d.remindersDue, label: "Erinnerungen")
            StatTile(icon: "leaf.fill", key: "garten", value: d.gartenOffen, label: "Garten offen")
            StatTile(icon: "gift.fill", key: "geschenkplaner", value: d.counts.geschenkeOffen, label: "Geschenke offen")
        }
    }

    // ── Anstehende Termine ──
    private func termine(_ items: [TerminShort]) -> some View {
        SectionCard(title: "Anstehende Termine", systemImage: "calendar", key: "termine") {
            ForEach(items.prefix(6)) { t in
                HStack(spacing: 12) {
                    GradientIcon(systemName: "calendar", gradientKey: "termine", size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(DateText.pretty(t.date) + (t.time.map { " · \($0)" } ?? ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await addToCalendar(t) }
                    } label: {
                        Image(systemName: "calendar.badge.plus").font(.title3)
                    }
                    .buttonStyle(.plain).foregroundStyle(Palette.colors(for: "termine").first!)
                }
                if t.id != items.prefix(6).last?.id { Divider() }
            }
            if !calMessage.isEmpty {
                Text(calMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func addToCalendar(_ t: TerminShort) async {
        guard let date = DateText.parse(date: t.date, time: t.time) else { return }
        let allDay = (t.time ?? "").isEmpty
        switch await CalendarSync.addEvent(title: t.title, date: date, allDay: allDay, notes: "Aus Familienplaner") {
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            calMessage = "\"\(t.title)\" im Kalender eingetragen."
        case .failure(let e):
            calMessage = (e as? CalendarSync.CalError) == .denied
                ? "Kalenderzugriff nicht erlaubt (in Einstellungen aktivieren)."
                : "Konnte nicht eintragen."
        }
    }

    // ── Nächste Abfuhr je Kategorie ──
    private func abfuhr(_ items: [AbfuhrNext]) -> some View {
        SectionCard(title: "Nächste Abfuhr", systemImage: "trash", key: "garten") {
            ForEach(items) { a in
                HStack(spacing: 12) {
                    Text(a.emoji).font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.label).font(.subheadline.weight(.semibold))
                        if let dt = a.datum { Text(DateText.pretty(dt)).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if let du = a.daysUntil {
                        let urgent = du <= 1
                        Text(du == 0 ? "heute" : du == 1 ? "morgen" : "in \(du) Tagen")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background((urgent ? Color.orange : Color(hex: a.color)).opacity(0.18), in: Capsule())
                            .foregroundStyle(urgent ? Color.orange : Color(hex: a.color))
                    }
                }
                if a.id != items.last?.id { Divider() }
            }
        }
    }

    // ── Nächste Reise (Countdown) ──
    private func reise(_ trip: NextTrip) -> some View {
        SectionCard(title: "Nächste Reise", systemImage: "airplane", key: "reisen") {
            HStack(spacing: 14) {
                GradientIcon(systemName: "airplane.departure", gradientKey: "reisen", size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(trip.title).font(.headline).lineLimit(1)
                    if let dest = trip.destination, !dest.isEmpty {
                        Text(dest).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let days = trip.daysUntil {
                    VStack(spacing: 0) {
                        Text("\(max(days, 0))").font(.system(size: 30, weight: .heavy, design: .rounded))
                        Text(days == 1 ? "Tag" : "Tage").font(.caption2).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(Palette.colors(for: "reisen").first!)
                }
            }
        }
    }

    // ── Bald ablaufende Lebensmittel ──
    private func vorrat(_ items: [VorratShort]) -> some View {
        SectionCard(title: "Bald ablaufend", systemImage: "clock.badge.exclamationmark", key: "vorratskammer") {
            ForEach(items.prefix(6)) { v in
                HStack(spacing: 12) {
                    GradientIcon(systemName: "fork.knife", gradientKey: "vorratskammer", size: 36)
                    Text(v.name).font(.subheadline.weight(.medium)).lineLimit(1)
                    Spacer()
                    if let mhd = v.mhd { Text(DateText.pretty(mhd)).font(.caption.weight(.semibold)).foregroundStyle(.orange) }
                }
                if v.id != items.prefix(6).last?.id { Divider() }
            }
        }
    }
}

/// Bunte Kennzahl-Kachel (Verlauf).
private struct StatTile: View {
    let icon: String, key: String, value: Int, label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.title3).foregroundStyle(.white.opacity(0.95))
            Text("\(value)").font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.gradient(for: key), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Palette.colors(for: key).first!.opacity(0.35), radius: 10, y: 5)
    }
}

/// Inhaltskarte mit Titel + Verlaufs-Icon.
struct SectionCard<Content: View>: View {
    let title: String, systemImage: String, key: String
    let content: Content
    init(title: String, systemImage: String, key: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.systemImage = systemImage; self.key = key; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Palette.colors(for: key).first!)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardSurface()
    }
}

/// „yyyy-MM-dd" → hübsches deutsches Datum + Parsing für Kalender/Erinnerungen.
enum DateText {
    private static let inFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "de_DE"); return f }()
    private static let outFmt: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.setLocalizedDateFormatFromTemplate("EEEEdMMMM"); return f }()
    static func pretty(_ s: String) -> String {
        guard let d = inFmt.date(from: String(s.prefix(10))) else { return s }
        return outFmt.string(from: d)
    }
    private static let dayFmt: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "d"; return f }()
    private static let monFmt: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "MMM"; return f }()
    private static let wdShortFmt: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "EE"; return f }()
    private static let wdLongFmt: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "EEEE"; return f }()
    private static let longFmt: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "d. MMMM yyyy"; return f }()
    private static func fmt(_ s: String, _ f: DateFormatter) -> String { inFmt.date(from: String(s.prefix(10))).map { f.string(from: $0) } ?? "" }
    static func day(_ s: String) -> String { fmt(s, dayFmt) }
    static func monthShort(_ s: String) -> String { fmt(s, monFmt) }
    static func weekdayShort(_ s: String) -> String { fmt(s, wdShortFmt) }
    static func weekdayLong(_ s: String) -> String { fmt(s, wdLongFmt) }
    static func longNoWeekday(_ s: String) -> String { fmt(s, longFmt) }

    /// Datum (+ optional Uhrzeit „HH:mm") in lokaler Zeit.
    static func parse(date: String, time: String? = nil) -> Date? {
        guard let day = inFmt.date(from: String(date.prefix(10))) else { return nil }
        guard let time, time.count >= 4 else { return day }
        let parts = time.split(separator: ":")
        guard let h = Int(parts.first ?? ""), parts.count > 1, let m = Int(parts[1]) else { return day }
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
    }
}
