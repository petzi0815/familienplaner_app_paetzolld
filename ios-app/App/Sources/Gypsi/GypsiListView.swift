import SwiftUI

/// Futter-Liste: Stats-Chips, Suche, Status-Segment, Marke/Geschmack-Menüs, Karten.
/// Löschen via nativer Bestätigungsabfrage; Umschalten/Löschen inline auf der Karte.
struct GypsiListView: View {
    @EnvironmentObject private var store: GypsiStore
    @State private var deleteTarget: GypsiFutter?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                statsRow
                AreaSearchField(placeholder: "Suchen …", text: $store.search)
                statusBar
                if !store.availableMarken.isEmpty || !store.availableGeschmack.isEmpty || store.filtersActive {
                    filterBar
                }
                list
            }
            .padding(.top, 4)
            .padding(.bottom, 96)   // Platz für den FAB
        }
        .refreshable { await store.loadAll() }
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

    // ── Liste ──
    @ViewBuilder private var list: some View {
        let items = store.visible
        if store.all.isEmpty {
            AreaEmptyState(emoji: "🐾", title: "Noch kein Futter eingetragen",
                           hint: "Tippe unten auf +, um Gypsis erstes Futter hinzuzufügen.")
                .frame(minHeight: 260)
        } else if items.isEmpty {
            AreaEmptyState(emoji: "🔍", title: "Nix gefunden!", hint: "Andere Filter probieren 🎯")
                .frame(minHeight: 240)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(items) { f in
                    GypsiFutterCard(
                        f: f,
                        busy: store.busyIDs.contains(f.id),
                        onToggle: { Task { await store.toggle(f) } },
                        onDelete: { deleteTarget = f })
                }
            }
            .padding(.horizontal, 14).padding(.top, 4)
        }
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
