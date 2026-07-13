import SwiftUI

/// Pflegeplan-Tab: nach Monat gruppierte Aufgaben-Timeline (Jan–Dez 2026) mit clientseitigem
/// Überfällig-Roll-up (offene Vergangenheits-Aufgaben wandern in den aktuellen Monat).
struct GartenPflegeView: View {
    @EnvironmentObject private var store: GartenStore
    private var currentMonth: Int { Calendar.current.component(.month, from: Date()) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                bereichPills
                statusPills
                timeline
            }
            .padding(.bottom, 24)
        }
        .refreshable { await store.reloadAufgaben() }
        .task(id: store.aufgabenFilter) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled { await store.reloadAufgaben() }
        }
    }

    private var bereichPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill("📋 Alle", "alle")
                pill("🌿 Rasen", "rasen")
                pill("🌳 Bäume", "baeume")
                pill("🌱 Anzucht", "anzucht")
            }
            .padding(.horizontal, 14)
        }
    }

    private func pill(_ label: String, _ value: String) -> some View {
        FilterPill(label: label, selected: store.aufgabenFilter.bereich == value, color: Color(hex: "34C759")) {
            store.aufgabenFilter.bereich = value
        }
    }

    private var statusPills: some View {
        HStack(spacing: 8) {
            FilterPill(label: "📋 Alle", selected: store.aufgabenFilter.erledigt == -1, color: Color(hex: "34C759")) {
                store.aufgabenFilter.erledigt = -1
            }
            FilterPill(label: "⏳ Offen", selected: store.aufgabenFilter.erledigt == 0, color: Color(hex: "F59E0B")) {
                store.aufgabenFilter.erledigt = 0
            }
            FilterPill(label: "✅ Erledigt", selected: store.aufgabenFilter.erledigt == 1, color: Color(hex: "16A34A")) {
                store.aufgabenFilter.erledigt = 1
            }
            Spacer()
        }
        .padding(.horizontal, 14)
    }

    /// Aufgaben eines Monats inkl. Überfällig-Roll-up (1:1 zur PWA-Logik).
    private func tasks(for monat: Int) -> [GartenAufgabe] {
        var list = store.aufgaben.filter { $0.computedMonat == monat }
        if monat == currentMonth {
            let overdue = store.aufgaben.filter { $0.computedMonat < currentMonth && !$0.erledigt }
            for a in overdue where !list.contains(where: { $0.id == a.id }) {
                var copy = a
                copy.overdue = true
                copy.originalMonat = a.computedMonat
                list.append(copy)
            }
        }
        if monat < currentMonth {
            list = list.filter { $0.erledigt }
        }
        return list
    }

    @ViewBuilder private var timeline: some View {
        if store.aufgaben.isEmpty {
            AreaEmptyState(emoji: "📋", title: "Keine Aufgaben gefunden!", hint: "Andere Filter probieren 🎯")
                .frame(minHeight: 220)
        } else {
            VStack(spacing: 14) {
                ForEach(1...12, id: \.self) { monat in
                    let list = tasks(for: monat)
                    if !list.isEmpty {
                        monthCard(monat, list)
                    }
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func monthCard(_ monat: Int, _ list: [GartenAufgabe]) -> some View {
        let isCurrent = monat == currentMonth
        let offen = list.filter { !$0.erledigt }.count
        return VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Text("\(GartenStyle.monatKurz[monat]) 2026").font(.headline)
                    if isCurrent { Text("← Aktuell").font(.caption.weight(.semibold)) }
                }
                .foregroundStyle(isCurrent ? .white : .primary)
                Spacer()
                Text("\(offen) offen").font(.caption.weight(.semibold))
                    .foregroundStyle(isCurrent ? .white.opacity(0.9) : .secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background {
                if isCurrent {
                    LinearGradient(colors: [Color(hex: "34C759"), Color(hex: "22C55E")], startPoint: .leading, endPoint: .trailing)
                } else {
                    Color(.secondarySystemBackground)
                }
            }

            VStack(spacing: 8) {
                ForEach(list) { a in
                    GartenAufgabeCard(
                        aufgabe: a,
                        onToggle: { Task { await store.toggleAufgabe(a) } },
                        onShift: { delta in Task { await store.shiftAufgabe(a, delta: delta) } }
                    )
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color(.tertiarySystemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(isCurrent ? Color(hex: "34C759") : Color.black.opacity(0.05), lineWidth: isCurrent ? 2 : 1))
    }
}

// MARK: - Aufgaben-Karte

struct GartenAufgabeCard: View {
    let aufgabe: GartenAufgabe
    var onToggle: () -> Void
    var onShift: (Int) -> Void

    private var cfg: GartenStyle.KategorieInfo { GartenStyle.kategorie(aufgabe.kategorie) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: aufgabe.erledigt ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(aufgabe.erledigt ? Color(hex: "10B981") : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                badges
                Text(aufgabe.titel)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(aufgabe.erledigt)
                    .foregroundStyle(aufgabe.erledigt ? .secondary : .primary)

                if aufgabe.kategorie == "duengen", let dn = aufgabe.duengerName, !aufgabe.erledigt {
                    HStack(spacing: 6) {
                        Pill(text: "💩 \(dn)", color: Color(hex: "B45309"), filled: false)
                        if aufgabe.isDuengenMissing {
                            Pill(text: "⚠️ Nicht vorrätig!", color: Color(hex: "DC2626"), filled: false)
                        }
                    }
                }
                if let e = aufgabe.ernteInfo, !aufgabe.erledigt {
                    Pill(text: "🌾 Ernte: \(e)", color: Color(hex: "059669"), filled: false)
                }
                if aufgabe.samenId != nil, !aufgabe.erledigt { shiftControls }
                if let b = aufgabe.beschreibung, !b.isEmpty {
                    Text(b).font(.caption).foregroundStyle(aufgabe.erledigt ? Color.secondary.opacity(0.7) : .secondary)
                }
                if aufgabe.erledigt, let am = aufgabe.erledigtAm {
                    Text("✅ Erledigt am \(DateText.longNoWeekday(am))").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(cardStroke, lineWidth: 1))
        .opacity(aufgabe.erledigt ? 0.65 : 1)
    }

    private var cardBackground: Color {
        if aufgabe.overdue { return Color(hex: "F97316").opacity(0.1) }
        if aufgabe.erledigt { return Color(.tertiarySystemFill) }
        return Color(.secondarySystemBackground)
    }
    private var cardStroke: Color {
        aufgabe.overdue ? Color(hex: "F97316").opacity(0.5) : Color.black.opacity(0.05)
    }

    private var badges: some View {
        HStack(spacing: 6) {
            if aufgabe.overdue {
                Pill(text: "⚠️ Überfällig (\(GartenStyle.kurz(aufgabe.originalMonat ?? aufgabe.monat)))", color: Color(hex: "EA580C"))
            }
            if let q = aufgabe.quellBadge {
                Pill(text: "\(q.emoji) \(q.label)", color: q.color)
            }
            Pill(text: "\(cfg.emoji) \(cfg.label)", color: cfg.color)
            if aufgabe.prioritaet == "hoch" && !aufgabe.overdue {
                Pill(text: "🔥 Wichtig", color: Color(hex: "DC2626"), filled: false)
            }
        }
    }

    private var shiftControls: some View {
        HStack(spacing: 8) {
            Text("📅 Geplant:").font(.caption2).foregroundStyle(.secondary)
            Button { onShift(-1) } label: { shiftButton("minus") }
                .buttonStyle(.plain)
                .disabled(aufgabe.computedMonat <= 1)
            HStack(spacing: 2) {
                Text(GartenStyle.kurz(aufgabe.computedMonat)).font(.caption2.weight(.bold))
                if aufgabe.isShifted {
                    Text("(statt \(GartenStyle.kurz(aufgabe.monat)))").font(.system(size: 9)).foregroundStyle(.blue.opacity(0.7))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(aufgabe.isShifted ? Color.blue.opacity(0.12) : Color(.tertiarySystemFill), in: Capsule())
            .foregroundStyle(aufgabe.isShifted ? Color.blue : Color.primary)
            Button { onShift(1) } label: { shiftButton("plus") }
                .buttonStyle(.plain)
                .disabled(aufgabe.computedMonat >= 12)
        }
    }

    private func shiftButton(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.caption.weight(.bold))
            .frame(width: 26, height: 26)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.secondary)
    }
}
