import SwiftUI

/// Listenansicht: Sektion „Anstehend" + einklappbare Sektion „Vergangen / Erledigt".
struct TermineListView: View {
    @EnvironmentObject private var store: TermineStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if store.upcomingItems.isEmpty && store.allPastItems.isEmpty {
                    AreaEmptyState(emoji: "🗓️", title: "Noch keine Termine", hint: "Lege den ersten Termin an!")
                        .frame(minHeight: 260)
                } else {
                    if !store.upcomingItems.isEmpty {
                        sectionHeader("Anstehend")
                        ForEach(store.upcomingItems) { TerminCard(termin: $0) }
                    }
                    if !store.allPastItems.isEmpty {
                        pastHeader
                        ForEach(store.visiblePastItems) { TerminCard(termin: $0) }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 28)
        }
        .refreshable { await store.reloadList(); await store.reloadMonth() }
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
                Text("Vergangen / Erledigt (\(store.allPastItems.count))").font(.caption.weight(.bold))
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
        .opacity(dimmed ? 0.6 : 1)
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
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button { Task { await store.toggleStatus(termin) } } label: {
                Label(termin.isDone ? "Offen" : "Erledigt",
                      systemImage: termin.isDone ? "arrow.uturn.left" : "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(termin.isDone ? Color.orange : Color.green)

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
