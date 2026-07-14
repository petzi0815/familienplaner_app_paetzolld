import SwiftUI

/// Übersicht-Tab: Summen-Karte (Monat/Jahr + gestapelter Balken + Legende), Top-Posten, Kategorie-Akkordeon.
struct VertraegeOverviewView: View {
    @EnvironmentObject private var store: VertraegeStore
    @State private var detail: Vertrag?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VertraegeSummaryCard()
                VertraegeTopPostenCard()
                ForEach(store.gruppen) { g in
                    VertragCategoryCard(gruppe: g, onOpen: { detail = $0 })
                }
            }
            .padding(14)
            .padding(.bottom, 28)
        }
        .refreshable { await store.loadAll() }
        .sheet(item: $detail) { v in
            VertragDetailSheet(vertragID: v.id).environmentObject(store)
        }
    }
}

// MARK: - Summen-Karte

struct VertraegeSummaryCard: View {
    @EnvironmentObject private var store: VertraegeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monatlich").font(.caption).foregroundStyle(.secondary)
                    Text(VertragFmt.eur(store.totalMonatlich)).font(.system(size: 30, weight: .heavy))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Jährlich").font(.caption).foregroundStyle(.secondary)
                    Text(VertragFmt.eur(store.totalJaehrlich)).font(.title3.weight(.bold)).foregroundStyle(.secondary)
                }
            }

            if store.totalMonatlich > 0 {
                VertraegeCategoryBar(gruppen: store.gruppenNachKosten, total: store.totalMonatlich)
                legend
            }

            if let stand = store.standText {
                Text("Stand: \(stand)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var legend: some View {
        let total = store.totalMonatlich
        let visible = store.gruppenNachKosten.filter { total > 0 && $0.monatlich / total * 100 >= 1 }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], alignment: .leading, spacing: 6) {
            ForEach(visible) { g in
                HStack(spacing: 5) {
                    Circle().fill(g.color).frame(width: 10, height: 10)
                    Text(g.name).font(.caption2.weight(.semibold)).lineLimit(1)
                    Text("\(Int((g.monatlich / total * 100).rounded()))%").font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// Ein gestapelter Balken: Segmentbreite ∝ Monatskosten; Segmente < 1 % werden weggelassen.
struct VertraegeCategoryBar: View {
    let gruppen: [VertragGruppe]
    let total: Double

    private struct Seg: Identifiable { let id: String; let color: Color; let fraction: Double }

    private var segments: [Seg] {
        guard total > 0 else { return [] }
        return gruppen.compactMap { g in
            let f = g.monatlich / total
            return f * 100 >= 1 ? Seg(id: g.name, color: g.color, fraction: f) : nil
        }
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(segments) { s in
                    Rectangle().fill(s.color).frame(width: max(2, geo.size.width * s.fraction))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 24)
        .background(Color(.tertiarySystemFill))
        .clipShape(Capsule())
    }
}

// MARK: - Top-Posten

struct VertraegeTopPostenCard: View {
    @EnvironmentObject private var store: VertraegeStore

    var body: some View {
        let top = Array(store.gruppenNachKosten.prefix(5))
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("TOP-POSTEN").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                ForEach(top) { g in
                    HStack(spacing: 10) {
                        Circle().fill(g.color).frame(width: 12, height: 12)
                        Text(g.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(VertragFmt.eurMo(g.monatlich)).font(.subheadline.weight(.bold))
                    }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

// MARK: - Kategorie-Karte (Akkordeon)

struct VertragCategoryCard: View {
    @EnvironmentObject private var store: VertraegeStore
    let gruppe: VertragGruppe
    var onOpen: (Vertrag) -> Void

    private var open: Bool { store.expanded.contains(gruppe.name) }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    if open { store.expanded.remove(gruppe.name) } else { store.expanded.insert(gruppe.name) }
                }
            } label: {
                HStack(spacing: 12) {
                    Text(gruppe.icon).font(.system(size: 20))
                        .frame(width: 40, height: 40)
                        .background(gruppe.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(gruppe.name).font(.subheadline.weight(.bold))
                        Text("\(gruppe.contracts.count) \(gruppe.contracts.count == 1 ? "Vertrag" : "Verträge")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(VertragFmt.eurMo(gruppe.monatlich)).font(.subheadline.weight(.bold))
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                Divider().padding(.horizontal, 12)
                VStack(spacing: 8) {
                    ForEach(gruppe.contracts) { v in
                        VertragRow(vertrag: v, accent: gruppe.color, onOpen: { onOpen(v) })
                    }
                }
                .padding(12)
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
