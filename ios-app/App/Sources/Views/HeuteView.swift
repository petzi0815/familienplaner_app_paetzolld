import SwiftUI
import UIKit

/// „Heute" — datengetriebenes Home aus GET /api/v1/dashboard/today:
/// KPI-Kacheln (antippbar → Bereich) + ein vereinheitlichter „Anstehendes"-Feed (Termine, Abfuhr,
/// Reisen, Vorrat, injizierte Erinnerungen) + Kalender-Abo (ganzen Feed als ICS abonnieren).
struct HeuteView: View {
    @EnvironmentObject private var app: AppState
    @State private var calMessage = ""
    @State private var showSearch = false
    @State private var showAddTask = false
    @State private var aufgabenFilter: AufgabenFilter = .offen

    enum AufgabenFilter: Hashable { case offen, erledigt }

    private let statCols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let d = app.dashboard {
                    VStack(spacing: 20) {
                        if app.alarmo?.configured != false { AlarmoTile() }
                        if let b = app.updateBuild { updateBanner(b) }
                        if let next = (d.agenda ?? []).first { nextHighlight(next) }
                        kpiGrid(d.kpis ?? [])
                        agendaCard(d.agenda ?? [])
                        if !d.vorratBaldAblaufend.isEmpty { vorratCard(d.vorratBaldAblaufend) }
                        aufgabenCard(open: d.aufgaben ?? [], done: d.aufgabenErledigt ?? [])
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
            .navigationTitle(greetingTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityIdentifier("home-search")
                }
            }
            .sheet(isPresented: $showSearch) { SearchView() }
            .sheet(isPresented: $showAddTask) { AufgabeAddSheet() }
            .areaToast($app.aufgabenError, isError: true)
            .refreshable { await app.loadDashboard(); await app.loadAlarmo() }
            .task { if app.dashboard == nil { await app.loadDashboard() } }
            .task { if app.alarmo == nil { await app.loadAlarmo() } }
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h { case 5..<11: return "Guten Morgen"; case 11..<17: return "Hallo"; case 17..<22: return "Guten Abend"; default: return "Gute Nacht" }
    }
    /// Begrüßung inkl. Person (nur bei Per-User-Keys lars/elita, sonst neutral).
    private var greetingTitle: String {
        if let o = app.me?.owner, o == "lars" || o == "elita" { return "\(greeting), \(app.me!.displayName)" }
        return greeting
    }

    // ── „Als Nächstes" — hervorgehobenes nächstes Anstehendes über den KPI-Kacheln ──
    private func nextHighlight(_ item: AgendaItem) -> some View {
        HStack(spacing: 14) {
            GradientIcon(systemName: nextIcon(item.source), gradientKey: item.domain, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("Als Nächstes").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Text(item.title).font(.headline).lineLimit(1)
                AgendaMeta(item: item)
                if let loc = item.location, !loc.isEmpty { LocationLink(location: loc) }
            }
            Spacer(minLength: 6)
            TerminDaysBadge(date: item.date)
        }
        .padding(16)
        .cardSurface()
    }
    private func nextIcon(_ source: String) -> String {
        switch source {
        case "abfuhr": return "trash.fill"
        case "reise": return "airplane"
        case "vorrat": return "fork.knife"
        case "reminder": return "bell.fill"
        default: return "calendar"
        }
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

    // ── Aufgaben (Familien-Aufgaben + fällige Garten-Aufgaben) — abhakbar, per + hinzufügbar,
    //    Umschalter Offen/Erledigt (erledigte lassen sich wieder öffnen, falls versehentlich abgehakt) ──
    private func aufgabenCard(open: [TaskItem], done: [TaskItem]) -> some View {
        SectionCard(title: "Aufgaben", systemImage: "checklist", key: "aufgaben") {
            Picker("Aufgaben-Filter", selection: $aufgabenFilter) {
                Text("Offen").tag(AufgabenFilter.offen)
                Text("Erledigt").tag(AufgabenFilter.erledigt)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("aufgaben-filter")

            if aufgabenFilter == .offen {
                Button { showAddTask = true } label: {
                    Label("Aufgabe hinzufügen", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.colors(for: "aufgaben").first!)
                .accessibilityIdentifier("aufgabe-add")
                Divider()
                aufgabenList(open, emptyText: "Keine offenen Aufgaben. 🎉")
            } else {
                Divider()
                aufgabenList(done, emptyText: "In den letzten Wochen nichts abgehakt.")
            }
        }
    }

    /// Liste von Aufgaben-Zeilen (Offen oder Erledigt), gedeckelt auf 10 mit „+ N weitere".
    @ViewBuilder private func aufgabenList(_ tasks: [TaskItem], emptyText: String) -> some View {
        if tasks.isEmpty {
            Text(emptyText)
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
        } else {
            let shown = Array(tasks.prefix(10))
            ForEach(shown) { task in
                AufgabeRow(task: task) { await app.toggleTask(task) }
                if task.id != shown.last?.id { Divider() }
            }
            if tasks.count > shown.count {
                Text("+ \(tasks.count - shown.count) weitere").font(.caption).foregroundStyle(.secondary).padding(.top, 2)
            }
        }
    }

    // ── Bald ablaufende Lebensmittel (Vorrat) — Name + Lagerort + MHD-Dringlichkeit; Tippen → Vorrat-Bereich ──
    private func vorratCard(_ items: [VorratShort]) -> some View {
        SectionCard(title: "Bald ablaufend", systemImage: "clock.badge.exclamationmark", key: "vorratskammer") {
            let shown = Array(items.prefix(10))
            ForEach(shown) { it in
                Button { app.openBereich("vorratskammer") } label: {
                    HStack(spacing: 10) {
                        Text(it.kategorie.map { VorratKat.info($0).emoji } ?? "🍽️").font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(it.name).font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                if let k = it.kategorie { Text(VorratKat.info(k).label) }
                                if let d = VorratMhd.formatDate(it.mhd) { Text(d) }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        if let info = VorratMhd.info(it.mhd) {
                            Pill(text: info.label, color: info.color, filled: true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("vorrat-ablaufend-\(it.id)")
                if it.id != shown.last?.id { Divider() }
            }
            if items.count > shown.count {
                Text("+ \(items.count - shown.count) weitere").font(.caption).foregroundStyle(.secondary).padding(.top, 2)
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
            Text(String(kpi.value)).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.white)
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
    var body: some View {
        HStack(spacing: 12) {
            GradientIcon(systemName: icon, gradientKey: item.domain, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                AgendaMeta(item: item)
                if let loc = item.location, !loc.isEmpty { LocationLink(location: loc) }
            }
            Spacer(minLength: 6)
            TerminDaysBadge(date: item.date)
        }
        .padding(.vertical, 2)
        .opacity(item.read == true ? 0.6 : 1)
    }
}

/// Meta-Zeile eines Agenda-Eintrags: die Uhrzeit (falls vorhanden) steht fett + `fixedSize` VORNE,
/// damit sie nie vom langen Datum abgeschnitten wird (lineLimit(1) kappte bisher „… · 15:45"); Datum
/// und Person/Ort-Text folgen sekundär und dürfen kürzen.
struct AgendaMeta: View {
    let item: AgendaItem
    private var dateAndExtra: String {
        var parts = [DateText.pretty(item.date)]
        if let s = item.subtitle, !s.isEmpty { parts.append(s) }
        return parts.joined(separator: " · ")
    }
    var body: some View {
        HStack(spacing: 5) {
            if let t = item.time, !t.isEmpty {
                Text(t).font(.caption.weight(.bold)).foregroundStyle(.primary).fixedSize()
                Text("·").font(.caption).foregroundStyle(.secondary)
            }
            Text(dateAndExtra).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

/// Eine Aufgaben-Zeile: Abhaken-Kreis + Titel + Beschreibung + Badges (Zuständig, Fällig/Überfällig,
/// Wiederholung, Quelle/Projekt). Tippen auf den Kreis hakt die Aufgabe ab.
struct AufgabeRow: View {
    let task: TaskItem
    let onComplete: () async -> Void
    @State private var busy = false

    private func ownerLabel(_ o: String) -> String {
        switch o {
        case "lars": return "Lars"
        case "elita": return "Elita"
        case "familie": return "Familie"
        default: return o.prefix(1).uppercased() + o.dropFirst()
        }
    }
    private func ownerColor(_ o: String) -> Color {
        switch o {
        case "lars": return Color(hex: "007AFF")
        case "elita": return Color(hex: "EC4899")
        default: return Color(hex: "6B7280")
        }
    }
    private var dueText: String? {
        if task.overdue {
            if let du = task.daysUntil, du < 0 { return "Überfällig · \(-du) T" }
            return "Überfällig"
        }
        if let d = task.dueDate, !d.isEmpty { return DateText.pretty(d) }
        if let l = task.dueLabel, !l.isEmpty { return l }
        return nil
    }
    private var doneWhen: String? {
        guard let da = task.doneAt, !da.isEmpty else { return nil }
        return DateText.pretty(String(da.prefix(10)))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                Task { busy = true; await onComplete(); busy = false }
            } label: {
                Image(systemName: busy ? "circle.dotted" : (task.isDone ? "checkmark.circle.fill" : "circle"))
                    .font(.title3)
                    .foregroundStyle(task.isDone ? Color.green : (task.overdue ? Color.red : Color.secondary))
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityIdentifier("aufgabe-complete-\(task.id)")
            .accessibilityLabel(task.isDone ? "Aufgabe \(task.title) wieder öffnen" : "Aufgabe \(task.title) abhaken")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    .strikethrough(task.isDone).foregroundStyle(task.isDone ? .secondary : .primary)
                if let d = task.description, !d.isEmpty {
                    Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let o = task.owner, !o.isEmpty {
                        Pill(text: ownerLabel(o), systemImage: "person.fill", color: ownerColor(o))
                    }
                    if task.isDone {
                        Pill(text: doneWhen.map { "Erledigt · \($0)" } ?? "Erledigt",
                             systemImage: "checkmark", color: Color(hex: "34C759"), filled: false)
                    } else if let due = dueText {
                        Pill(text: due, systemImage: "calendar",
                             color: task.overdue ? .red : Color(hex: "F59E0B"), filled: task.overdue)
                    }
                    if let r = task.recurring, r != "einmalig", !r.isEmpty {
                        Image(systemName: "repeat").font(.caption2).foregroundStyle(.secondary)
                    }
                    if task.source == "garten" {
                        Pill(text: "Garten", systemImage: "leaf.fill", color: Color(hex: "34C759"), filled: false)
                    } else if let p = task.project, !p.isEmpty {
                        Pill(text: p, color: Color(hex: "6366F1"), filled: false)
                    }
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 3)
    }
}

/// Neue Familien-Aufgabe anlegen: Titel + Pflicht-Beschreibung + Zuständig + optionale Fälligkeit,
/// Wiederholung, Priorität, Projekt. Schreibt über das generische CRUD (POST /api/v1/aufgaben).
struct AufgabeAddSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var beschreibung = ""
    @State private var owner = "familie"
    @State private var hasDue = false
    @State private var due = Date()
    @State private var priority = "normal"
    @State private var recurring = "einmalig"
    @State private var project = ""
    @State private var saving = false
    @State private var error: String?

    private static let isoFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; return f
    }()
    private let owners = [("lars", "👨 Lars"), ("elita", "👩 Elita"), ("familie", "👨‍👩‍👦 Familie")]
    private let prios = [("niedrig", "Niedrig"), ("normal", "Normal"), ("hoch", "Hoch")]
    private let recurrings = [("einmalig", "Einmalig"), ("taeglich", "Täglich"), ("woechentlich", "Wöchentlich"), ("monatlich", "Monatlich"), ("jaehrlich", "Jährlich")]

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !beschreibung.trimmingCharacters(in: .whitespaces).isEmpty && !saving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Was ist zu tun? *", text: $title)
                    TextField("Beschreibung *", text: $beschreibung, axis: .vertical).lineLimit(2...5)
                    Picker("Zuständig", selection: $owner) {
                        ForEach(owners, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }
                Section("Fälligkeit") {
                    Toggle("Terminiert", isOn: $hasDue)
                    if hasDue { DatePicker("Fällig am", selection: $due, displayedComponents: .date) }
                    Picker("Wiederholung", selection: $recurring) {
                        ForEach(recurrings, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }
                Section("Details") {
                    Picker("Priorität", selection: $priority) {
                        ForEach(prios, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    TextField("Projekt (optional)", text: $project)
                }
                if let e = error {
                    Text(e).font(.caption).foregroundStyle(.red)
                }
            }
            .navigationTitle("✅ Neue Aufgabe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") { Task { await save() } }.disabled(!canSave)
                }
            }
        }
    }

    private func save() async {
        saving = true; error = nil
        var fields: [String: Any] = [
            "title": title.trimmingCharacters(in: .whitespaces),
            "description": beschreibung.trimmingCharacters(in: .whitespaces),
            "owner": owner,
            "priority": priority,
            "recurring": recurring,
            "source": "manuell",
        ]
        if hasDue { fields["due_date"] = Self.isoFmt.string(from: due) }
        let p = project.trimmingCharacters(in: .whitespaces)
        if !p.isEmpty { fields["project"] = p }
        let ok = await app.createAufgabe(fields)
        saving = false
        if ok { dismiss() } else { error = app.aufgabenError ?? "Konnte nicht anlegen." }
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
