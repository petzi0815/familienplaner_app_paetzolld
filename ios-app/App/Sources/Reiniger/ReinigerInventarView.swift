import SwiftUI

/// Inventar-Tab: Produkte nach Kategorie gruppiert, "+ Neu"-Button, Detail-/Bearbeiten-Sheets.
struct ReinigerInventarView: View {
    @EnvironmentObject private var store: ReinigerStore
    @State private var detail: ReinigerProdukt?
    @State private var editRef: ReinigerEditRef?

    var body: some View {
        Group {
            if store.inventarGroups.isEmpty {
                ScrollView {
                    AreaEmptyState(emoji: "🧽", title: "Noch keine Reiniger erfasst",
                                   hint: "Tippe auf \"Neuer Reiniger\", um zu starten.",
                                   actionLabel: "Hinzufügen",
                                   action: { editRef = ReinigerEditRef(product: nil) })
                        .frame(minHeight: 260)
                }
                .refreshable { await store.loadAll() }
            } else {
                VStack(spacing: 0) {
                    header
                    List {
                        ForEach(store.inventarGroups, id: \.kategorie) { group in
                            Section {
                                ForEach(group.items) { p in
                                    ReinigerProduktCard(produkt: p) { detail = p }
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                        .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                Task { await store.deleteProduct(p.id) }
                                            } label: { Label("Löschen", systemImage: "trash") }
                                            Button {
                                                Task { await store.setStatus(p.id, "nachkaufen") }
                                            } label: { Label("Nachkaufen", systemImage: "cart.badge.plus") }
                                            .tint(.green)
                                        }
                                }
                            } header: {
                                sectionHeader(group.kategorie, group.items.count)
                            }
                            .textCase(nil)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { await store.loadAll() }
                }
            }
        }
        .sheet(item: $detail) { p in
            ReinigerDetailSheet(productID: p.id).environmentObject(store)
        }
        .sheet(item: $editRef) { ref in
            ReinigerEditView(product: ref.product).environmentObject(store)
        }
    }

    /// Fester Kopf (nicht scrollend): "+ Neuer Reiniger".
    private var header: some View {
        HStack {
            Spacer()
            Button { editRef = ReinigerEditRef(product: nil) } label: {
                Label("Neuer Reiniger", systemImage: "plus.circle.fill").font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    /// Kategorie-Kopf je Section (Emoji + Label + Anzahl).
    private func sectionHeader(_ kategorie: String, _ count: Int) -> some View {
        let cat = ReinigerStyle.cat(kategorie)
        return Text("\(cat.emoji) \(cat.label.uppercased()) (\(String(count)))")
            .font(.caption.weight(.bold)).foregroundStyle(.secondary)
    }
}

// MARK: - Produkt-Karte (Listenzeile)

struct ReinigerProduktCard: View {
    let produkt: ReinigerProdukt
    var onOpen: () -> Void

    var body: some View {
        let cat = ReinigerStyle.cat(produkt.kategorie)
        HStack(alignment: .top, spacing: 12) {
            thumbnail(cat)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Text(produkt.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Spacer(minLength: 0)
                    Pill(text: cat.label, color: cat.color)
                }
                Text(produkt.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let f = produkt.flecken, !f.isEmpty {
                    Text("Hilft bei: \(f)").font(.caption).foregroundStyle(.primary).lineLimit(2)
                }
                if let g = produkt.geeignetFuer, !g.isEmpty {
                    Text("Für: \(g)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let ng = produkt.nichtGeeignetFuer, !ng.isEmpty {
                    Text("Nicht für: \(ng)").font(.caption).foregroundStyle(.red).lineLimit(1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }

    @ViewBuilder private func thumbnail(_ cat: ReinigerStyle.CatInfo) -> some View {
        Group {
            if let path = produkt.imagePath {
                AuthImage(path: path, contentMode: .fill)
            } else {
                LinearGradient(colors: [Color(hex: "BAE6FD"), Color(hex: "D9F99D")], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Text(cat.emoji).font(.system(size: 28)))
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Bearbeiten/Anlegen-Ziel als Identifiable-Wrapper (fuer `.sheet(item:)`; product == nil -> Neu).
struct ReinigerEditRef: Identifiable {
    let id = UUID()
    let product: ReinigerProdukt?
}
