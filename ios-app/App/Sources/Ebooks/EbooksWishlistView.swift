import SwiftUI

/// Wunschlisten-Tab: Stat-Pillen, Suche, Status/Jahr/Kategorie-Filter, Karten-Liste, Detail-Sheet.
struct EbooksWishlistView: View {
    @EnvironmentObject private var store: EbooksStore
    @State private var detail: EbookItem?
    @State private var deleteTarget: EbookItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                statsPills
                AreaSearchField(placeholder: "In Wunschliste suchen …", text: $store.filters.search)
                statusPills
                dropdownRow
                list
            }
            .padding(.bottom, 24)
        }
        .refreshable { await store.loadAll() }
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

    // ── Liste ──
    @ViewBuilder private var list: some View {
        if store.items.isEmpty {
            if store.filters.isActive {
                AreaEmptyState(emoji: "📖", title: "Keine Bücher gefunden", hint: "Versuche andere Filter 🎯").frame(minHeight: 260)
            } else {
                AreaEmptyState(emoji: "📖", title: "Keine Bücher gefunden", hint: "Die Wunschliste ist noch leer.").frame(minHeight: 260)
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(store.items) { item in
                    EbookCard(item: item, onOpen: { detail = item }, onDelete: { deleteTarget = item })
                }
            }
            .padding(.horizontal, 14).padding(.top, 4)
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
            Text("\(emoji) \(value)").font(.subheadline.weight(.bold))
            Text(label.uppercased()).font(.caption2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(color)
    }
}
