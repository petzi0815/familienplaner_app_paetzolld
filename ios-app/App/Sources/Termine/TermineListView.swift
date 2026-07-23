import SwiftUI

/// Listenansicht: Sektion „Anstehend" + einklappbare Sektion „Vergangen / Erledigt".
struct TermineListView: View {
    @EnvironmentObject private var store: TermineStore

    var body: some View {
        Group {
            if store.upcomingItems.isEmpty && store.allPastItems.isEmpty {
                ScrollView {
                    AreaEmptyState(emoji: "🗓️", title: "Noch keine Termine", hint: "Lege den ersten Termin an!")
                        .frame(maxWidth: .infinity).frame(minHeight: 320)
                }
                .refreshable { await store.reloadList(); await store.reloadMonth() }
            } else {
                // List statt ScrollView → native Wisch-Aktionen; Karten-Look via clear rows.
                List {
                    if !store.upcomingItems.isEmpty {
                        Section {
                            ForEach(store.upcomingItems) { row($0) }
                        } header: { sectionHeader("Anstehend") }
                        .textCase(nil)
                    }
                    if !store.allPastItems.isEmpty {
                        Section {
                            ForEach(store.visiblePastItems) { row($0) }
                        } header: { pastHeader }
                        .textCase(nil)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await store.reloadList(); await store.reloadMonth() }
            }
        }
    }
    // Deep-Links (`familienplaner://termin/<id>`) werden bewusst in TermineRootView eingelöst:
    // diese View wird nur im Listenmodus ohne aktive Suche gerendert, ein Widget-/Push-Tipp im
    // Kalendermodus würde hier nie ankommen.

    /// Termin-Karte als List-Zeile (transparente Zeile) mit nativen Wisch-Aktionen (Erledigen + Löschen).
    private func row(_ t: Termin) -> some View {
        TerminCard(termin: t)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) { store.deleteTarget = t } label: {
                    Label("Löschen", systemImage: "trash")
                }
                Button { Task { await store.toggleStatus(t) } } label: {
                    Label(t.isDone ? "Offen" : "Erledigt", systemImage: t.isDone ? "arrow.uturn.left" : "checkmark.circle.fill")
                }
                .tint(t.isDone ? .orange : .green)
            }
    }

    private func sectionHeader(_ t: String) -> some View {
        HStack {
            Text(t.uppercased()).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 4)
    }

    private var pastHeader: some View {
        Button { withAnimation(.snappy(duration: 0.2)) { store.showPast.toggle() } } label: {
            HStack(spacing: 6) {
                Image(systemName: store.showPast ? "chevron.down" : "chevron.right").font(.caption.weight(.bold))
                Text("Vergangen / Erledigt (\(String(store.allPastItems.count)))").font(.caption.weight(.bold))
                Spacer()
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
    }
}

// MARK: - Termin-Karte (Liste + Kalender-Tagesdetail)

struct TerminCard: View {
    let termin: Termin
    @EnvironmentObject private var store: TermineStore

    private var cat: TerminCategory { store.category(termin.category) }
    private var catColor: Color { TermineStyle.color(cat.color) }
    /// Vergangen & noch offen → gedimmt.
    private var dimmed: Bool { (TermineDates.daysUntil(termin.date) ?? 0) < 0 && termin.status == "offen" }
    /// Persönlich stummgeschaltet („nicht mehr erinnern").
    private var muted: Bool { store.isMuted(termin) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 2) {
                    Text(cat.emoji).font(.title2)
                    if let t = termin.time, !t.isEmpty {
                        Text(t).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 46)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        Text(termin.title)
                            .font(.subheadline.weight(.semibold))
                            .strikethrough(termin.isDone)
                            .opacity(termin.isDone ? 0.6 : 1)
                        Spacer(minLength: 6)
                        TerminDaysBadge(date: termin.date)
                    }
                    if let d = termin.beschreibung, !d.isEmpty {
                        Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    metaChips
                    if let n = termin.notes, !n.isEmpty {
                        Text(n).font(.caption).italic().foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(dimmed ? 0.6 : (termin.read && !termin.isDone ? 0.8 : 1))
    }

    private var metaChips: some View {
        FlowLayout(spacing: 6) {
            Pill(text: "📅 \(DateText.pretty(termin.date))", color: .gray, filled: false)
            if let e = termin.endDate, !e.isEmpty, e != termin.date {
                Pill(text: "→ \(DateText.pretty(e))", color: .gray, filled: false)
            }
            if let l = termin.location, !l.isEmpty {
                Pill(text: "📍 \(l)", color: .gray, filled: false)
            }
            if let p = termin.person, !p.isEmpty {
                Pill(text: "\(TermineStyle.personEmoji(p)) \(p)", color: catColor, filled: false)
            }
            Pill(text: cat.label, color: catColor, filled: false)
            if muted {
                Pill(text: "🔕 Stumm", color: .gray, filled: false)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            // Geteilt: Erledigt (ändert den Status für alle).
            Button { Task { await store.toggleStatus(termin) } } label: {
                Label(termin.isDone ? "Offen" : "Erledigt",
                      systemImage: termin.isDone ? "arrow.uturn.left" : "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(termin.isDone ? Color.orange : Color.green)

            // Persönlich: „gelesen"-Häkchen (nur für mich, lässt den Termin offen).
            Button { Task { await store.toggleRead(termin) } } label: {
                Image(systemName: termin.read ? "eye.fill" : "eye")
            }
            .buttonStyle(.plain)
            .foregroundStyle(termin.read ? Theme.accent : .secondary)
            .accessibilityIdentifier("termin-read-\(termin.id)")
            .accessibilityLabel(termin.read ? "Als ungelesen markieren" : "Als gelesen markieren")

            // Persönlich: Benachrichtigung (Dropdown) — 2 & 1 Tag vorher an/aus + Stummschaltung.
            Menu {
                Button { Task { await store.setNotify(termin, true) } } label: {
                    Label("2 & 1 Tag vorher", systemImage: termin.notify ? "checkmark" : "bell")
                }
                Button { Task { await store.setNotify(termin, false) } } label: {
                    Label("Keine Benachrichtigung", systemImage: termin.notify ? "bell.slash" : "checkmark")
                }
                Divider()
                // „Stumm" schaltet auch die Standard-Erinnerungen (Vorabend/Termintag) ab —
                // gleiche Route wie der Push-Knopf „Nicht mehr erinnern" am Sperrbildschirm.
                if muted {
                    Button { Task { await store.setMuted(termin, false) } } label: {
                        Label("Wieder erinnern", systemImage: "bell.badge")
                    }
                    .accessibilityIdentifier("termin-unmute-\(termin.id)")
                } else {
                    Button(role: .destructive) { Task { await store.setMuted(termin, true) } } label: {
                        Label("Stumm – nicht mehr erinnern", systemImage: "bell.slash.fill")
                    }
                    .accessibilityIdentifier("termin-mute-\(termin.id)")
                }
            } label: {
                Image(systemName: muted ? "bell.slash.fill" : (termin.notify ? "bell.fill" : "bell"))
            }
            .foregroundStyle(muted ? Color.secondary : (termin.notify ? Theme.accent : Color.secondary))
            .accessibilityIdentifier("termin-notify-\(termin.id)")
            .accessibilityLabel(muted ? "Stumm – Benachrichtigung wählen" : "Benachrichtigung wählen")

            Spacer()

            Button { store.formRef = TermineFormRef(termin: termin, initialDate: nil) } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain).foregroundStyle(Theme.accent)

            Button { store.deleteTarget = termin } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain).foregroundStyle(.red)
        }
        .font(.subheadline)
    }
}

// MARK: - Tage-Badge (clientseitig aus daysUntil)

struct TerminDaysBadge: View {
    let date: String
    @State private var pulse = false

    private var info: (text: String, color: Color, bold: Bool, pulse: Bool)? {
        guard let d = TermineDates.daysUntil(date) else { return nil }
        switch d {
        case ..<0:   return ("vorbei", Color(hex: "9CA3AF"), false, false)
        case 0:      return ("🔴 Heute", Color(hex: "EF4444"), true, true)
        case 1:      return ("⚡ Morgen", Color(hex: "F97316"), true, false)
        case 2...7:  return ("\(d) Tage", Color(hex: "F59E0B"), false, false)
        case 8...30: return ("\(d) Tage", Color(hex: "9CA3AF"), false, false)
        default:     return nil
        }
    }

    var body: some View {
        if let i = info {
            Text(i.text)
                .font(.caption2.weight(i.bold ? .bold : .semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(i.color.opacity(0.18), in: Capsule())
                .foregroundStyle(i.color)
                .scaleEffect(i.pulse && pulse ? 1.08 : 1.0)
                .onAppear {
                    if i.pulse {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
                    }
                }
        }
    }
}
