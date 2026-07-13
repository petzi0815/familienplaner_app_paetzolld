import SwiftUI

/// Inventar-Tab: Status-Pills, Suche, Typ/Größe/Marke/Kategorie-Filter, Item-Raster, Detail-Sheet.
struct SamuInventarView: View {
    @EnvironmentObject private var store: SamuStore
    @State private var detail: SamuItem?
    @State private var markeSheet: MarkeRef?
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                statusPills
                AreaSearchField(placeholder: "Suchen …", text: $store.filters.search)
                filterControls
                if store.filters.typ != nil { kategoriePills }
                grid
            }
            .padding(.bottom, 24)
        }
        .refreshable { await store.loadAll() }
        .task(id: store.filters.search) {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if !Task.isCancelled { await store.applySearch() }
        }
        .sheet(item: $detail) { item in
            SamuItemDetailSheet(itemID: item.id)
                .environmentObject(store)
        }
        .sheet(item: $markeSheet) { ref in
            SamuMarkeSheet(name: ref.name).environmentObject(store)
        }
    }

    // ── Status-Pills (aus Stats) ──
    private var statusPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.stats.nachStatus, id: \.status) { entry in
                    let info = SamuStyle.statusInfo(entry.status)
                    let selected = store.filters.status == entry.status
                    Button { Task { await store.setStatus(entry.status) } } label: {
                        VStack(spacing: 1) {
                            Text("\(info.emoji) \(entry.count)").font(.subheadline.weight(.bold))
                            Text(info.label.uppercased()).font(.caption2)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(selected ? AnyShapeStyle(info.color) : AnyShapeStyle(Color(.secondarySystemBackground)), in: Capsule())
                        .foregroundStyle(selected ? info.color.onFill : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.top, 6)
        }
    }

    // ── Typ-Pills + Reset, Größe/Marke-Dropdowns ──
    private var filterControls: some View {
        VStack(spacing: 8) {
            HStack {
                FilterPill(label: "Alle", selected: store.filters.typ == nil, color: Theme.accent) { Task { await store.setTyp(nil) } }
                FilterPill(label: "👕 Kleidung", selected: store.filters.typ == "kleidung", color: Color(hex: "2563EB")) { Task { await store.setTyp("kleidung") } }
                FilterPill(label: "🧸 Spielzeug", selected: store.filters.typ == "spielzeug", color: Color(hex: "9333EA")) { Task { await store.setTyp("spielzeug") } }
                Spacer()
                if store.filters.isActive {
                    Button { Task { await store.reset() } } label: {
                        Label("Reset", systemImage: "xmark.circle").font(.footnote.weight(.semibold))
                    }
                }
            }
            HStack(spacing: 10) {
                if !store.availableGroessen.isEmpty {
                    Menu {
                        Button("📏 Alle Größen") { Task { await store.setGroesse(nil) } }
                        ForEach(store.availableGroessen, id: \.self) { g in
                            Button("Gr. \(g)") { Task { await store.setGroesse(g) } }
                        }
                    } label: {
                        dropdownLabel(icon: "ruler", text: store.filters.groesse.map { "Gr. \($0)" } ?? "Größe")
                    }
                }
                if !store.availableMarken.isEmpty {
                    Menu {
                        Button("🏷️ Alle Marken") { store.setMarke(nil) }
                        ForEach(store.availableMarken, id: \.self) { m in
                            Button(m) { store.setMarke(m) }
                        }
                    } label: {
                        dropdownLabel(icon: "tag", text: store.filters.marke ?? "Marke")
                    }
                }
                Spacer()
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

    // ── Kategorie-Pills (nur wenn Typ gewählt) ──
    private var kategoriePills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterPill(label: "Alle", selected: store.filters.kategorie == nil) { Task { await store.setKategorie(nil) } }
                ForEach(store.availableKategorien, id: \.self) { k in
                    FilterPill(label: k, selected: store.filters.kategorie == k) { Task { await store.setKategorie(k) } }
                }
            }
            .padding(.horizontal, 14)
        }
    }

    // ── Raster ──
    @ViewBuilder private var grid: some View {
        let list = store.visibleItems
        if list.isEmpty {
            AreaEmptyState(emoji: "🔍", title: "Nix gefunden!", hint: "Versuch andere Filter 🎯")
                .frame(minHeight: 260)
        } else {
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(list) { item in
                    SamuItemCard(item: item, onOpen: { detail = item },
                                 onMarke: item.hasMarke ? { markeSheet = MarkeRef(name: item.marke ?? "") } : nil)
                }
            }
            .padding(.horizontal, 14).padding(.top, 4)
        }
    }
}
