import SwiftUI
import UIKit

/// „Heute" — datengetriebenes Home aus GET /api/v1/dashboard/today:
/// KPI-Kacheln (antippbar → Bereich) + ein vereinheitlichter „Anstehendes"-Feed (Termine, Abfuhr,
/// Reisen, Vorrat, injizierte Erinnerungen) + Kalender-Abo (ganzen Feed als ICS abonnieren).
struct HeuteView: View {
    @EnvironmentObject private var app: AppState
    @State private var calMessage = ""

    private let statCols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let d = app.dashboard {
                    VStack(spacing: 20) {
                        if let b = app.updateBuild { updateBanner(b) }
                        kpiGrid(d.kpis ?? [])
                        agendaCard(d.agenda ?? [])
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

    // ── Update-Banner (neuer TestFlight-Build) ──
    private func updateBanner(_ build: Int) -> some View {
        Button {
            let link = app.testflightURL.flatMap { URL(string: $0) } ?? URL(string: "itms-beta://")
            if let link { UIApplication.shared.open(link) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.app.fill").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update verfügbar").font(.subheadline.weight(.bold))
                    Text("Build \(build) liegt im TestFlight – zum Aktualisieren tippen.").font(.caption)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.caption.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(Palette.gradient(for: "foto"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Palette.colors(for: "foto").first!.opacity(0.35), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("update-banner")
    }

    // ── KPI-Kacheln (datengetrieben, antippbar → springt in den Bereich) ──
    private func kpiGrid(_ kpis: [KpiTile]) -> some View {
        LazyVGrid(columns: statCols, spacing: 12) {
            ForEach(kpis) { k in
                Button { app.openKpiTarget(k.target) } label: { KpiTileView(kpi: k) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("kpi-\(k.key)")
            }
        }
    }

    // ── Anstehendes (vereinheitlichter Feed) + Kalender-Abo ──
    private func agendaCard(_ items: [AgendaItem]) -> some View {
        SectionCard(title: "Anstehendes", systemImage: "calendar", key: "termine") {
            Button { Task { await subscribeCalendar() } } label: {
                Label("Kalender abonnieren", systemImage: "calendar.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.colors(for: "termine").first!)
            .accessibilityIdentifier("calendar-subscribe")
            if !calMessage.isEmpty {
                Text(calMessage).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            if items.isEmpty {
                Text("Nichts in den nächsten Wochen.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            } else {
                ForEach(Array(items.prefix(12))) { item in
                    AgendaRow(item: item)
                        .contextMenu {
                            if item.source == "termin" || item.source == "reise" {
                                Button { Task { await addToCalendar(item) } } label: {
                                    Label("Zum Kalender hinzufügen", systemImage: "calendar.badge.plus")
                                }
                            }
                        }
                    if item.id != items.prefix(12).last?.id { Divider() }
                }
            }
        }
    }

    /// Ganzen Kalender-Feed (Termine + Abfuhr + Reisen) als ICS abonnieren (webcal → iOS-Abo-Dialog).
    private func subscribeCalendar() async {
        do {
            let sub = try await app.api.feedSubscribe()
            if let url = URL(string: sub.webcal) { _ = await UIApplication.shared.open(url) }
            calMessage = "Kalender-Abo geöffnet – im Dialog bestätigen."
        } catch {
            calMessage = "Abo-Link konnte nicht geladen werden."
        }
    }

    /// Einzelnes Ereignis manuell in den lokalen Kalender eintragen (Kontextmenü-Fallback).
    private func addToCalendar(_ item: AgendaItem) async {
        guard let date = DateText.parse(date: item.date, time: item.time) else { return }
        let allDay = (item.time ?? "").isEmpty
        switch await CalendarSync.addEvent(title: item.title, date: date, allDay: allDay, notes: "Aus Familienplaner") {
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            calMessage = "\"\(item.title)\" im Kalender eingetragen."
        case .failure(let e):
            calMessage = (e as? CalendarSync.CalError) == .denied
                ? "Kalenderzugriff nicht erlaubt (in Einstellungen aktivieren)."
                : "Konnte nicht eintragen."
        }
    }
}

/// Datengetriebene KPI-Kachel (Verlauf, antippbar).
private struct KpiTileView: View {
    let kpi: KpiTile
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: kpi.icon).font(.title3).foregroundStyle(.white.opacity(0.95))
            Text("\(kpi.value)").font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            Text(kpi.label).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.gradient(for: kpi.domain), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Palette.colors(for: kpi.domain).first!.opacity(0.35), radius: 10, y: 5)
    }
}

/// Eine Zeile des vereinheitlichten „Anstehendes"-Feeds (quellenübergreifend).
struct AgendaRow: View {
    let item: AgendaItem

    private var icon: String {
        switch item.source {
        case "abfuhr": return "trash.fill"
        case "reise": return "airplane"
        case "vorrat": return "fork.knife"
        case "reminder": return "bell.fill"
        default: return "calendar"
        }
    }
    private var subtitle: String {
        var parts: [String] = [DateText.pretty(item.date)]
        if let t = item.time, !t.isEmpty { parts.append(t) }
        if let s = item.subtitle, !s.isEmpty { parts.append(s) }
        return parts.joined(separator: " · ")
    }
    var body: some View {
        HStack(spacing: 12) {
            GradientIcon(systemName: icon, gradientKey: item.domain, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            TerminDaysBadge(date: item.date)
        }
        .padding(.vertical, 2)
        .opacity(item.read == true ? 0.6 : 1)
    }
}

/// Inhaltskarte mit Titel + Verlaufs-Icon. (Von mehreren Bereichen genutzt — hier definiert.)
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
