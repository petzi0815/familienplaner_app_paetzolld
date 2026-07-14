import SwiftUI

/// Verträge-Tab: flache, durchsuch- & sortierbare Liste aller Verträge mit Kategorie-Filter (native Erweiterung).
struct VertraegeListView: View {
    @EnvironmentObject private var store: VertraegeStore
    @State private var detail: Vertrag?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                AreaSearchField(placeholder: "Anbieter, Nummer, Notiz …", text: $store.filters.search)
                kategoriePills
                sortBar
                list
            }
            .padding(.bottom, 28)
        }
        .refreshable { await store.loadAll() }
        .sheet(item: $detail) { v in
            VertragDetailSheet(vertragID: v.id).environmentObject(store)
        }
    }

    private var kategoriePills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterPill(label: "Alle", selected: store.filters.kategorie == nil) {
                    store.filters.kategorie = nil
                }
                ForEach(store.availableKategorien, id: \.self) { k in
                    FilterPill(label: k, selected: store.filters.kategorie == k,
                               color: VertragStyle.color(for: k, metaHex: nil)) {
                        store.filters.kategorie = (store.filters.kategorie == k) ? nil : k
                    }
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private var sortBar: some View {
        HStack {
            Menu {
                ForEach(VertragSort.allCases, id: \.self) { s in
                    Button {
                        store.filters.sort = s
                    } label: {
                        if store.filters.sort == s { Label(s.label, systemImage: "checkmark") } else { Text(s.label) }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(store.filters.sort.label)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color(.secondarySystemBackground), in: Capsule())
                .foregroundStyle(.primary)
            }
            Spacer()
            let n = store.listVisible.count
            Text("\(n) \(n == 1 ? "Vertrag" : "Verträge")").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder private var list: some View {
        let items = store.listVisible
        if items.isEmpty {
            AreaEmptyState(emoji: "🔍", title: "Nichts gefunden", hint: "Andere Suche oder Filter versuchen.")
                .frame(minHeight: 240)
        } else {
            VStack(spacing: 8) {
                ForEach(items) { v in
                    VertragRow(vertrag: v, accent: v.catColor, showKategorie: true, onOpen: { detail = v })
                }
            }
            .padding(.horizontal, 14).padding(.top, 2)
        }
    }
}

// MARK: - Vertrags-Zeile (Akkordeon + Liste)

struct VertragRow: View {
    @EnvironmentObject private var store: VertraegeStore
    let vertrag: Vertrag
    var accent: Color = Theme.accent
    var showKategorie: Bool = false
    var onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                if showKategorie {
                    Pill(text: "\(vertrag.catIcon) \(vertrag.kategorieName)", color: accent, filled: false)
                }
                Text(vertrag.anbieter ?? "—").font(.subheadline.weight(.semibold))
                if let t = vertrag.bezeichnung, !t.isEmpty {
                    Text(t).font(.caption).foregroundStyle(.secondary)
                }
                if let nr = vertrag.vertragsnummer, !nr.isEmpty {
                    // Eigener Button → verschluckt den Tap (kein Öffnen des Detail-Sheets), wie das Web-„stopPropagation".
                    Button { store.copy(nr) } label: {
                        Label(nr, systemImage: "doc.on.doc")
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                if let d = vertrag.notizen, !d.isEmpty {
                    Text(d).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let k = vertrag.kosten {
                    Text(VertragFmt.eur(k)).font(.headline)
                } else {
                    Text("—").font(.headline).foregroundStyle(.secondary)
                }
                if let i = vertrag.kostenIntervall, !i.isEmpty {
                    Text(i.capitalized).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }
}
