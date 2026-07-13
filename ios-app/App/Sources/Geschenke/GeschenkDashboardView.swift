import SwiftUI

/// Übersicht-Tab: Stats, offene Profil-Bestaetigungen, anstehende Ereignisse (Budget/Status).
struct GeschenkDashboardView: View {
    @EnvironmentObject private var store: GeschenkStore

    var body: some View {
        ScrollView {
            if store.loadingDashboard && store.dashboard == nil {
                ProgressView("Lädt …").frame(maxWidth: .infinity, minHeight: 240)
            } else if let d = store.dashboard {
                VStack(spacing: 14) {
                    stats(d)
                    ForEach(d.offeneBestaetigung) { ob in confirmCard(ob) }
                    upcoming(d)
                }
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 28)
            }
        }
        .task { await store.loadDashboard() }
        .refreshable { await store.loadDashboard() }
    }

    // ── Stats ──
    private func stats(_ d: GDashboard) -> some View {
        HStack(spacing: 10) {
            AreaStatTile(value: "\(d.statsKinder)", label: "Kinder", color: GStyle.accent)
            AreaStatTile(value: "\(d.statsEreignisse)", label: "Ereignisse", color: GStyle.accent)
            AreaStatTile(value: GStyle.eur(d.geplantSumme), label: "Geplant", color: GStyle.accent)
        }
    }

    // ── Offene Profil-Bestaetigung ──
    private func confirmCard(_ ob: GEreignis) -> some View {
        HStack(spacing: 12) {
            Text("⚠️").font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(ob.kindName ?? "Kind"): Profil bestätigen").font(.subheadline.weight(.bold))
                Text("\(GStyle.anlassEmoji(ob.anlass)) \(GStyle.anlassLabel(ob.anlass)) \(ob.jahr)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button { Task { await store.confirmProfil(ob.kindId) } } label: {
                Text("✅").font(.subheadline.weight(.bold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(GStyle.accent, in: Capsule())
                    .foregroundStyle(GStyle.accent.onFill)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(GStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // ── Anstehende Ereignisse ──
    @ViewBuilder private func upcoming(_ d: GDashboard) -> some View {
        HStack {
            Text("📅 Nächste Ereignisse").font(.subheadline.weight(.bold))
            Spacer()
        }
        if d.anstehende.isEmpty {
            AreaEmptyState(emoji: "🎉", title: "Keine anstehenden Ereignisse mit Geschenken",
                           hint: "Geschenkvorschläge werden 60 Tage vor dem Anlass automatisch recherchiert.")
                .frame(minHeight: 220)
        } else {
            ForEach(d.anstehende) { e in
                NavigationLink(value: GeschenkRoute.ereignis(e.id)) { eventCard(e) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func eventCard(_ e: GEreignis) -> some View {
        let ausgaben = e.geschenkeAusgaben ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(GStyle.anlassEmoji(e.anlass)) \(e.kindName ?? "") — \(GStyle.anlassLabel(e.anlass)) \(e.jahr)")
                        .font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                    Text(subline(e)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                GCountdownBadge(datum: e.datum)
            }
            if let bmax = e.budgetMax, bmax > 0 {
                GBudgetBar(ausgaben: ausgaben, budgetMax: Double(bmax))
            }
            statusChips(e)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle().fill(GStyle.anlassColor(e.anlass)).frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }

    private func subline(_ e: GEreignis) -> String {
        var parts: [String] = [GDate.fmt(e.datum)]
        if let a = e.alterZumEreignis { parts.append("\(a) Jahre") }
        let n = e.giftCount
        parts.append("\(n) \(n == 1 ? "Geschenk" : "Geschenke")")
        if let bmax = e.budgetMax { parts.append("Budget: \(e.budgetMin ?? 0)–\(bmax) €") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func statusChips(_ e: GEreignis) -> some View {
        let hasChips = GStyle.statuses.contains { (e.geschenkeStatus[$0] ?? 0) > 0 }
        if hasChips || e.erinnerungenAktiv == 0 {
            FlowLayout(spacing: 6) {
                ForEach(GStyle.statuses, id: \.self) { s in
                    let c = e.geschenkeStatus[s] ?? 0
                    if c > 0 {
                        GChip(text: "\(c)× \(GStyle.statusLabel(s))", color: GStyle.statusColor(s))
                    }
                }
                if e.erinnerungenAktiv == 0 {
                    GChip(text: "🔕 Stumm", color: .gray)
                }
            }
        }
    }
}
