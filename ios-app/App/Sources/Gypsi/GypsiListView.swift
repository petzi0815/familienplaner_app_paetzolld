import SwiftUI

/// Futter-Liste: Stats-Chips, Suche, Status-Segment, Marke/Geschmack-Menüs, Karten.
/// Karten liegen in einer nativen `List` → Wisch-Aktionen (Umschalten/Löschen); der feste
/// Kopf (Stats/Suche/Status/Filter) sitzt außerhalb der Liste. Löschen via Bestätigungsabfrage.
struct GypsiListView: View {
    @EnvironmentObject private var store: GypsiStore
    @State private var deleteTarget: GypsiFutter?

    var body: some View {
        VStack(spacing: 0) {
            header
            listContent
        }
        .confirmationDialog(deleteTitle,
                            isPresented: deleteBinding,
                            titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let t = deleteTarget { Task { await store.delete(t) } }
                deleteTarget = nil
            }
            Button("Abbrechen", role: .cancel) { deleteTarget = nil }
        }
    }

    // ── Fester Kopf (bleibt beim Scrollen stehen) ──
    private var header: some View {
        VStack(spacing: 10) {
            statsRow
            AreaSearchField(placeholder: "Suchen …", text: $store.search)
            statusBar
            if !store.availableMarken.isEmpty || !store.availableGeschmack.isEmpty || store.filtersActive {
                filterBar
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // ── Liste bzw. Leerzustände ──
    @ViewBuilder private var listContent: some View {
        let items = store.visible
        if store.all.isEmpty {
            ScrollView {
                AreaEmptyState(emoji: "🐾", title: "Noch kein Futter eingetragen",
                               hint: "Tippe unten auf +, um Gypsis erstes Futter hinzuzufügen.")
                    .frame(maxWidth: .infinity).frame(minHeight: 260)
            }
            .refreshable { await store.loadAll() }
        } else if items.isEmpty {
            ScrollView {
                AreaEmptyState(emoji: "🔍", title: "Nix gefunden!", hint: "Andere Filter probieren 🎯")
                    .frame(maxWidth: .infinity).frame(minHeight: 240)
            }
            .refreshable { await store.loadAll() }
        } else {
            // List statt ScrollView → native Wisch-Aktionen; Karten-Look via transparente Zeilen.
            List {
                ForEach(items) { f in row(f) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 88, for: .scrollContent)   // Platz für den FAB
            .refreshable { await store.loadAll() }
        }
    }

    /// Futter-Karte als List-Zeile (transparent) mit nativen Wisch-Aktionen (Umschalten + Löschen).
    private func row(_ f: GypsiFutter) -> some View {
        let info = GypsiStyle.info(f.status)
        return GypsiFutterCard(
            f: f,
            busy: store.busyIDs.contains(f.id),
            onToggle: { Task { await store.toggle(f) } },
            onDelete: { deleteTarget = f })
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) { deleteTarget = f } label: {
                    Label("Löschen", systemImage: "trash")
                }
                Button { Task { await store.toggle(f) } } label: {
                    Label(f.liked ? "Mag er nicht" : "Mag er",
                          systemImage: f.liked ? "hand.thumbsdown.fill" : "hand.thumbsup.fill")
                }
                .tint(info.toggleColor)
            }
    }

    // ── Stats-Chips (globale Zahlen) ──
    private var statsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Pill(text: "✓ \(store.likedCount) mag er", color: GypsiStyle.green, filled: false)
                Pill(text: "✗ \(store.dislikedCount) mag er nicht mehr", color: GypsiStyle.red, filled: false)
                Pill(text: "📦 \(store.total) gesamt", color: GypsiStyle.amber, filled: false)
            }
            .padding(.horizontal, 14).padding(.top, 6)
        }
    }

    // ── Status-Segment ──
    private var statusBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GypsiStatusFilter.allCases, id: \.self) { s in
                    let sel = store.statusFilter == s
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { store.statusFilter = s }
                    } label: {
                        Text(s.label)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .background(sel ? AnyShapeStyle(s.color) : AnyShapeStyle(Color(.secondarySystemBackground)),
                                        in: Capsule())
                            .foregroundStyle(sel ? s.color.onFill : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    // ── Marke / Geschmack + Filter löschen ──
    private var filterBar: some View {
        HStack(spacing: 10) {
            if !store.availableMarken.isEmpty {
                Menu {
                    Button("🏷️ Alle Marken") { store.markeFilter = nil }
                    ForEach(store.availableMarken, id: \.self) { m in
                        Button(m) { store.markeFilter = m }
                    }
                } label: {
                    dropdown(icon: "tag", text: store.markeFilter ?? "Marke")
                }
            }
            if !store.availableGeschmack.isEmpty {
                Menu {
                    Button("🥩 Alle Geschmäcker") { store.geschmackFilter = nil }
                    ForEach(store.availableGeschmack, id: \.self) { g in
                        Button(g) { store.geschmackFilter = g }
                    }
                } label: {
                    dropdown(icon: "fork.knife", text: store.geschmackFilter ?? "Geschmack")
                }
            }
            Spacer()
            if store.filtersActive {
                Button { store.clearFilters() } label: {
                    Label("Filter", systemImage: "xmark.circle").font(.footnote.weight(.semibold))
                }
            }
        }
        .padding(.horizontal, 14)
    }

    private func dropdown(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(text).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.caption2)
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color(.secondarySystemBackground), in: Capsule())
        .foregroundStyle(.primary)
    }

    // ── Löschen-Bestätigung ──
    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }
    private var deleteTitle: String {
        guard let t = deleteTarget else { return "Wirklich löschen?" }
        return "\"\(t.marke) \(t.sorte)\" wirklich löschen?"
    }
}
