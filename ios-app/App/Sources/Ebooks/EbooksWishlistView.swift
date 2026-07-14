import SwiftUI

/// Wunschlisten-Tab: Stat-Pillen, Suche, Status/Jahr/Kategorie-Filter, Karten-Liste, Detail-Sheet.
struct EbooksWishlistView: View {
    @EnvironmentObject private var store: EbooksStore
    @State private var detail: EbookItem?
    @State private var deleteTarget: EbookItem?

    var body: some View {
        VStack(spacing: 0) {
            // Feste Kopfleiste (Stat-Pillen, Bulk, Suche, Status-Pillen, Dropdowns) — bleibt beim Scrollen stehen.
            VStack(spacing: 10) {
                statsPills
                bulkRow
                AreaSearchField(placeholder: "In Wunschliste suchen …", text: $store.filters.search)
                statusPills
                dropdownRow
            }
            .padding(.bottom, 8)

            listOrEmpty
        }
        .task(id: store.filters.search) {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if !Task.isCancelled { await store.applySearch() }
        }
        .sheet(item: $detail) { item in
            EbookDetailSheet(itemID: item.id).environmentObject(store)
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { if let t = deleteTarget { Task { await store.deleteItem(t) } }; deleteTarget = nil }
            Button("Abbrechen", role: .cancel) { deleteTarget = nil }
        }
    }

    private var deleteTitle: String {
        guard let t = deleteTarget else { return "Wirklich löschen?" }
        return "\(t.title) wirklich löschen?"
    }

    // ── Bulk-Aktionen: alle prüfen / fertige löschen ──
    private var bulkRow: some View {
        HStack(spacing: 10) {
            Button { Task { await store.checkAllWishlist() } } label: {
                if store.bulkChecking { ProgressView() }
                else { Label("Alle prüfen", systemImage: "arrow.down.circle").font(.footnote.weight(.semibold)) }
            }
            .buttonStyle(.bordered).tint(EbookStyle.amber)
            .disabled(store.bulkChecking || store.statGesucht == 0)
            .accessibilityIdentifier("wishlist-check-all")

            Button { Task { await store.cleanupDownloaded() } } label: {
                Label("Fertige löschen", systemImage: "trash").font(.footnote.weight(.semibold))
            }
            .buttonStyle(.bordered).tint(.red)
            .disabled(store.statGeladen == 0)
            .accessibilityIdentifier("wishlist-cleanup")

            Spacer()
        }
        .padding(.horizontal, 14)
    }

    // ── Stat-Pillen (aus den geladenen, gefilterten Items) ──
    private var statsPills: some View {
        HStack(spacing: 8) {
            EbookStatPill(emoji: "📚", value: store.statGesamt, label: "gesamt", color: EbookStyle.rose)
            EbookStatPill(emoji: "🔍", value: store.statGesucht, label: "gesucht", color: EbookStyle.amber)
            EbookStatPill(emoji: "✅", value: store.statGeladen, label: "geladen", color: EbookStyle.green)
        }
        .padding(.horizontal, 14).padding(.top, 6)
    }

    // ── Status-Pillen ──
    private var statusPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterPill(label: "📚 Alle", selected: store.filters.status == nil, color: EbookStyle.rose) { Task { await store.setStatus(nil) } }
                FilterPill(label: "🔍 Gesucht", selected: store.filters.status == "gesucht", color: EbookStyle.amber) { Task { await store.setStatus("gesucht") } }
                FilterPill(label: "✅ Geladen", selected: store.filters.status == "heruntergeladen", color: EbookStyle.green) { Task { await store.setStatus("heruntergeladen") } }
            }
            .padding(.horizontal, 14)
        }
    }

    // ── Jahr/Kategorie-Dropdowns + Reset ──
    private var dropdownRow: some View {
        HStack(spacing: 10) {
            if !store.years.isEmpty {
                Menu {
                    Button("📅 Alle Jahre") { Task { await store.setYear(nil) } }
                    ForEach(store.years, id: \.self) { y in
                        Button(y) { Task { await store.setYear(y) } }
                    }
                } label: {
                    dropdownLabel(icon: "calendar", text: store.filters.year ?? "Jahr")
                }
            }
            if !store.categories.isEmpty {
                Menu {
                    Button("🏷️ Alle Kategorien") { Task { await store.setCategory(nil) } }
                    ForEach(store.categories, id: \.self) { cat in
                        Button(cat) { Task { await store.setCategory(cat) } }
                    }
                } label: {
                    dropdownLabel(icon: "tag", text: store.filters.category ?? "Kategorie")
                }
            }
            Spacer()
            if store.filters.hasClearable {
                Button { Task { await store.clearFilters() } } label: {
                    Label("Filter", systemImage: "xmark.circle").font(.footnote.weight(.semibold))
                }
            }
        }
        .padding(.horizontal, 14)
    }

    private func dropdownLabel(icon: String, text: String) -> some View {
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

    // ── Liste (SwiftUI List → native Swipe-Aktionen) ──
    @ViewBuilder private var listOrEmpty: some View {
        if store.items.isEmpty {
            // List rendert Leerzustände schlecht → ScrollView + gleicher Reload.
            ScrollView {
                if store.filters.isActive {
                    AreaEmptyState(emoji: "📖", title: "Keine Bücher gefunden", hint: "Versuche andere Filter 🎯").frame(minHeight: 260)
                } else {
                    AreaEmptyState(emoji: "📖", title: "Keine Bücher gefunden", hint: "Die Wunschliste ist noch leer.").frame(minHeight: 260)
                }
            }
            .refreshable { await store.loadAll() }
        } else {
            List {
                ForEach(store.items) { item in
                    EbookCard(item: item,
                              onOpen: { detail = item },
                              onDelete: { deleteTarget = item },
                              onCheck: { Task { await store.checkBook(item) } },
                              checking: store.checkingID == item.id)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { deleteTarget = item } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                            Button { Task { _ = await store.toggleStatus(item) } } label: {
                                Label(item.isDownloaded ? "Gesucht" : "Geladen",
                                      systemImage: item.isDownloaded ? "magnifyingglass" : "checkmark.circle")
                            }
                            .tint(item.isDownloaded ? EbookStyle.amber : EbookStyle.green)
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await store.loadAll() }
        }
    }
}

// MARK: - Stat-Pille (Kopfleiste)

struct EbookStatPill: View {
    let emoji: String
    let value: Int
    let label: String
    let color: Color
    var body: some View {
        VStack(spacing: 1) {
            Text("\(emoji) \(String(value))").font(.subheadline.weight(.bold))
            Text(label.uppercased()).font(.caption2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(color)
    }
}
