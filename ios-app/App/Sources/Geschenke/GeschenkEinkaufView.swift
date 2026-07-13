import SwiftUI

/// Einkauf-Tab: ausgewaehlte Geschenke (nach Kind+Anlass gruppiert) + bereits bestellte.
struct GeschenkEinkaufView: View {
    @EnvironmentObject private var store: GeschenkStore

    private var ausgewaehlt: [GGeschenk] { store.einkauf.filter { $0.status == "ausgewaehlt" } }
    private var bestellt: [GGeschenk] { store.einkauf.filter { $0.status == "bestellt" } }
    private var totalPreis: Double { ausgewaehlt.reduce(0) { $0 + ($1.preis ?? 0) } }

    /// Geordnete Gruppen (nach erster Vorkommens-Reihenfolge, wie die Web-App).
    private var gruppen: [GEinkaufGroup] {
        var order: [String] = []
        var map: [String: [GGeschenk]] = [:]
        for it in ausgewaehlt {
            let key = groupKey(it)
            if map[key] == nil { order.append(key); map[key] = [] }
            map[key]?.append(it)
        }
        return order.map { GEinkaufGroup(id: $0, items: map[$0] ?? []) }
    }

    private func groupKey(_ g: GGeschenk) -> String {
        let anlassPart = g.anlass.map { "\(GStyle.anlassEmoji($0)) \(GStyle.anlassLabel($0))" } ?? ""
        let jahrPart = g.jahr.map(String.init) ?? ""
        return "\(g.kindName ?? "") — \(anlassPart) \(jahrPart)"
    }

    var body: some View {
        ScrollView {
            if store.loadingEinkauf && store.einkauf.isEmpty {
                ProgressView("Lädt …").frame(maxWidth: .infinity, minHeight: 240)
            } else {
                VStack(spacing: 14) {
                    stats
                    section(title: "🛒 Noch einzukaufen")
                    if ausgewaehlt.isEmpty {
                        AreaEmptyState(emoji: "✨", title: "Keine ausgewählten Geschenke.",
                                       hint: "Wähle Vorschläge in der Übersicht aus.")
                            .frame(minHeight: 180)
                    } else {
                        ForEach(gruppen) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.id).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                ForEach(group.items) { g in ausgewaehltCard(g) }
                            }
                        }
                    }
                    if !bestellt.isEmpty {
                        section(title: "📦 Bereits bestellt (\(bestellt.count))")
                        ForEach(bestellt) { g in bestelltCard(g) }
                    }
                }
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 28)
            }
        }
        .task { await store.loadEinkauf() }
        .refreshable { await store.loadEinkauf() }
    }

    private var stats: some View {
        HStack(spacing: 10) {
            StatTile(value: "\(ausgewaehlt.count)", label: "Ausgewählt", color: Theme.accent)
            StatTile(value: GStyle.eur(totalPreis), label: "Gesamt", color: Theme.accent)
        }
    }

    private func section(title: String) -> some View {
        HStack { Text(title).font(.subheadline.weight(.bold)); Spacer() }
    }

    // ── Ausgewaehlt (zum Einkaufen) ──
    private func ausgewaehltCard(_ g: GGeschenk) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let path = g.imagePath {
                AuthImage(path: path, contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(g.titel).font(.subheadline.weight(.bold))
                GGiftMetaChips(g: g, compact: true)
            }
            Spacer(minLength: 6)
            VStack(spacing: 6) {
                actionButton("📦", tint: Color(hex: "D97706")) { Task { await store.setGeschenkStatus(g.id, "bestellt") } }
                actionButton("↩️", tint: .gray) { Task { await store.setGeschenkStatus(g.id, "vorschlag") } }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // ── Bestellt (gedimmt) ──
    private func bestelltCard(_ g: GGeschenk) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(g.titel).font(.subheadline.weight(.medium))
                Text(bestelltSub(g)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            VStack(spacing: 6) {
                actionButton("🎀", tint: Color(hex: "16A34A")) { Task { await store.setGeschenkStatus(g.id, "verpackt") } }
                actionButton("↩️", tint: .gray) { Task { await store.setGeschenkStatus(g.id, "ausgewaehlt") } }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(0.7)
    }

    private func bestelltSub(_ g: GGeschenk) -> String {
        var parts: [String] = ["👶 \(g.kindName ?? "")"]
        if let a = g.anlass { parts.append(GStyle.anlassLabel(a)) }
        if let p = g.preis { parts.append(GStyle.eur(p)) }
        return parts.joined(separator: " · ")
    }

    private func actionButton(_ label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.footnote.weight(.bold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(tint.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
