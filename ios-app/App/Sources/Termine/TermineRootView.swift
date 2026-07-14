import SwiftUI

/// Wurzel des nativen Termine-Bereichs — ersetzt den generischen Browser für `termine`.
/// Kopf + Stat-Pillen + Listen/Kalender-Umschalter + Live-Suche + Kategorie-Chips + aktive Ansicht.
struct TermineRootView: View {
    @StateObject private var store: TermineStore

    init(settings: Settings) { _store = StateObject(wrappedValue: TermineStore(settings: settings)) }

    private var toggleTabs: [(tab: TermineMode, label: String, systemImage: String?)] {
        [(.liste, "Liste", "list.bullet"), (.kalender, "Kalender", "calendar")]
    }

    var body: some View {
        VStack(spacing: 0) {
            AreaHeader(gradientKey: "termine", systemImage: "calendar", title: "Termine",
                       subtitle: "Familie Paetzold-Stilke")
            statBar
            SegmentBar(tabs: toggleTabs, selection: $store.mode, gradientKey: "termine")
            AreaSearchField(placeholder: "Termine suchen …", text: $store.search)
            if !store.searchActive && store.mode == .liste { categoryChips }
            Divider()
            content
        }
        .background(Palette.gradient(for: "termine").opacity(0.05).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.formRef = TermineFormRef(termin: nil, initialDate: store.selectedDate) } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { if store.termine.isEmpty && store.loading { await store.loadAll() } }
        .environmentObject(store)
        .areaToast($store.message, isError: store.messageIsError)
        .onChange(of: store.search) { _, _ in store.searchChanged() }
        .sheet(item: $store.formRef) { ref in
            TermineFormSheet(termin: ref.termin, initialDate: ref.initialDate).environmentObject(store)
        }
        .confirmationDialog(
            store.deleteTarget.map { "\"\($0.title)\" löschen?" } ?? "",
            isPresented: Binding(get: { store.deleteTarget != nil }, set: { if !$0 { store.deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                if let t = store.deleteTarget { Task { await store.delete(t) } }
                store.deleteTarget = nil
            }
            Button("Abbrechen", role: .cancel) { store.deleteTarget = nil }
        }
    }

    // ── Stat-Pillen ──
    private var statBar: some View {
        HStack(spacing: 8) {
            Pill(text: "\(store.statOffen) offen", systemImage: "checklist", color: .blue)
            if store.statThisWeek > 0 {
                Pill(text: "\(store.statThisWeek) diese Woche", systemImage: "bolt.fill", color: .orange)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.bottom, 2)
    }

    // ── Kategorie-Filter (nur Listenmodus; Kalender ignoriert die Kategorie) ──
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterPill(label: "Alle", selected: store.selectedCategory == nil, color: Theme.accent) {
                    Task { await store.setCategory(nil) }
                }
                ForEach(store.categories) { c in
                    FilterPill(label: "\(c.emoji) \(c.label)", selected: store.selectedCategory == c.id,
                               color: TermineStyle.color(c.color)) {
                        Task { await store.setCategory(c.id) }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }

    @ViewBuilder private var content: some View {
        if store.loading && store.termine.isEmpty {
            ProgressView("Lädt …").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.searchActive {
            TermineSearchResults()
        } else {
            switch store.mode {
            case .liste: TermineListView()
            case .kalender: TermineCalendarView()
            }
        }
    }
}

// MARK: - Suchergebnis-Overlay (bis zu 10 kompakte Zeilen)

struct TermineSearchResults: View {
    @EnvironmentObject private var store: TermineStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if store.searching {
                    HStack(spacing: 8) { ProgressView(); Text("Suche …").foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity).padding(.top, 30)
                } else if let r = store.searchResults, r.isEmpty {
                    AreaEmptyState(emoji: "🔍", title: "Keine Treffer",
                                   hint: "für \"\(store.search.trimmingCharacters(in: .whitespaces))\"")
                        .frame(minHeight: 220)
                } else if let r = store.searchResults {
                    Text("\(r.count) Treffer").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    ForEach(Array(r.prefix(10))) { TerminSearchRow(termin: $0) }
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 28)
        }
    }
}

struct TerminSearchRow: View {
    let termin: Termin
    @EnvironmentObject private var store: TermineStore
    private var cat: TerminCategory { store.category(termin.category) }

    var body: some View {
        Button { store.formRef = TermineFormRef(termin: termin, initialDate: nil) } label: {
            HStack(spacing: 10) {
                Text(cat.emoji).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(termin.title).font(.subheadline.weight(.semibold)).strikethrough(termin.isDone)
                    Text(subline).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                TerminDaysBadge(date: termin.date)
            }
            .contentShape(Rectangle())
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private var subline: String {
        var parts = [DateText.pretty(termin.date)]
        if let t = termin.time, !t.isEmpty { parts.append(t) }
        if let p = termin.person, !p.isEmpty { parts.append(p) }
        return parts.joined(separator: " · ")
    }
}
