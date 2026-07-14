import SwiftUI

// Rezepte-Tab: reine Vorschlagskarten (vom Agenten befüllt) mit externem Link + Bild.
// Kein Anlege-UI — Rezepte kommen out-of-band; hier nur lesend.

struct VorratRezepteView: View {
    @EnvironmentObject private var store: VorratStore

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if store.rezepte.isEmpty {
                    AreaEmptyState(emoji: "🍳", title: "Noch keine Rezeptvorschläge",
                                   hint: "Sobald Lebensmittel mit MHD erfasst sind, recherchiere ich passende Rezepte!")
                        .frame(minHeight: 300)
                } else {
                    ForEach(store.rezepte) { r in VorratRezeptCard(rezept: r) }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
        .refreshable { await store.loadAll() }
    }
}

// MARK: - Rezeptkarte

struct VorratRezeptCard: View {
    let rezept: VorratRezept

    var body: some View {
        Group {
            if let url = rezept.linkURL {
                Link(destination: url) { cardBody }.buttonStyle(.plain)
            } else {
                cardBody
            }
        }
    }

    private var cardBody: some View {
        HStack(alignment: .top, spacing: 12) {
            thumb
            VStack(alignment: .leading, spacing: 5) {
                Text(rezept.titel).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                if let q = rezept.quelle { Text(q).font(.caption).foregroundStyle(Color(hex: "F97316")) }
                if let d = rezept.beschreibung { Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                if !rezept.zutaten.isEmpty {
                    VorratFlow(spacing: 6) {
                        ForEach(rezept.zutaten, id: \.self) { z in
                            Text(z)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color(hex: "F97316").opacity(0.15), in: Capsule())
                                .foregroundStyle(Color(hex: "C2410C"))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if rezept.linkURL != nil {
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder private var thumb: some View {
        if let b = rezept.bildUrl, !b.isEmpty {
            AuthImage(path: b, contentMode: .fill)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Palette.gradient(for: "vorratskammer").opacity(0.18)
                .frame(width: 64, height: 64)
                .overlay(Text("🍳").font(.title2))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

// MARK: - Einfaches Fließ-Layout (Zutaten-Chips umbrechen statt scrollen)

struct VorratFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        let width = maxWidth.isFinite ? maxWidth : x
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            sv.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
