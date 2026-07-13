import SwiftUI

/// Übersicht-Tab: Kategorie × Größe Pivot-Matrix (nur Kleidung, aktiv+eingelagert).
/// Zellen mit Anzahl sind antippbar → filtert das Inventar und wechselt in den Inventar-Tab.
struct SamuMatrixView: View {
    @EnvironmentObject private var store: SamuStore

    private var kategorien: [String] { Array(Set(store.matrix.map { $0.kategorie })).sorted() }
    private var groessen: [String] {
        Array(Set(store.matrix.map { $0.groesse })).sorted { a, b in
            if let ia = Int(a), let ib = Int(b) { return ia < ib }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }
    private var counts: [String: [String: Int]] {
        var m: [String: [String: Int]] = [:]
        for c in store.matrix { m[c.kategorie, default: [:]][c.groesse, default: 0] += c.count }
        return m
    }
    private func count(_ kat: String, _ gr: String) -> Int { counts[kat]?[gr] ?? 0 }
    private func rowTotal(_ kat: String) -> Int { groessen.reduce(0) { $0 + count(kat, $1) } }
    private func colTotal(_ gr: String) -> Int { kategorien.reduce(0) { $0 + count($1, gr) } }
    private var grandTotal: Int { store.matrix.reduce(0) { $0 + $1.count } }

    var body: some View {
        if kategorien.isEmpty {
            AreaEmptyState(emoji: "📊", title: "Keine Daten", hint: "Aktive Kleidung erscheint hier als Kategorie × Größe.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("📊 Kategorie × Größe").font(.headline).padding(.horizontal, 14).padding(.top, 10)
                Text("Aktiv + Im Schrank · Tippe auf eine Zahl zum Filtern")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14)
                ScrollView([.horizontal, .vertical]) {
                    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                        headerRow
                        ForEach(kategorien, id: \.self) { kat in bodyRow(kat) }
                        totalsRow
                    }
                    .padding(10)
                }
            }
        }
    }

    private var headerRow: some View {
        GridRow {
            cellText("Kat.", bold: true, bg: Color(.secondarySystemBackground)).frame(width: 96, alignment: .leading)
            ForEach(groessen, id: \.self) { g in cellText(g, bold: true, bg: Color(.secondarySystemBackground)) }
            cellText("Σ", bold: true, bg: Color(.secondarySystemBackground))
        }
    }

    private func bodyRow(_ kat: String) -> some View {
        GridRow {
            cellText(kat, bold: false, align: .leading).frame(width: 96, alignment: .leading)
            ForEach(groessen, id: \.self) { g in
                let n = count(kat, g)
                if n > 0 {
                    Button { Task { await store.focusMatrix(kategorie: kat, groesse: g) } } label: {
                        Text("\(n)").font(.subheadline.weight(.bold)).frame(minWidth: 40, minHeight: 34)
                            .background(Theme.accent.opacity(0.12)).foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                } else {
                    cellText("·", muted: true)
                }
            }
            cellText("\(rowTotal(kat))", bold: true, bg: Color(.secondarySystemBackground))
        }
    }

    private var totalsRow: some View {
        GridRow {
            cellText("Gesamt", bold: true, bg: Color(.secondarySystemBackground)).frame(width: 96, alignment: .leading)
            ForEach(groessen, id: \.self) { g in cellText("\(colTotal(g))", bold: true, bg: Color(.secondarySystemBackground)) }
            Text("\(grandTotal)").font(.subheadline.weight(.heavy)).foregroundStyle(Theme.accent)
                .frame(minWidth: 40, minHeight: 34).background(Color(.secondarySystemBackground))
        }
    }

    private func cellText(_ s: String, bold: Bool = false, muted: Bool = false, align: Alignment = .center, bg: Color = .clear) -> some View {
        Text(s)
            .font(bold ? .subheadline.weight(.bold) : .subheadline)
            .foregroundStyle(muted ? Color.secondary : Color.primary)
            .frame(minWidth: 40, minHeight: 34, alignment: align)
            .padding(.horizontal, 6)
            .background(bg)
            .overlay(Rectangle().stroke(Color(.separator).opacity(0.3), lineWidth: 0.5))
    }
}
