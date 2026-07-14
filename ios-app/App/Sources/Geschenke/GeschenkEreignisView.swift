import SwiftUI

/// Ereignis-Detail (gepusht): Kopf, Erinnerungs-Toggle, Geschenkliste (+ Bewerten-Modus), Formular.
struct GeschenkEreignisView: View {
    let ereignisID: Int
    @EnvironmentObject private var store: GeschenkStore

    @State private var ereignis: GEreignis?
    @State private var loading = true
    @State private var swipeMode = false
    @State private var filterStatus: String?
    @State private var reminderOn = true
    @State private var giftSheet: GiftEditRef?
    @State private var deleteTarget: GGeschenk?
    @State private var vergebenTarget: GGeschenk?

    private var geschenke: [GGeschenk] { ereignis?.geschenke ?? [] }
    private var ausgaben: Double {
        geschenke.filter { ["ausgewaehlt", "bestellt", "verpackt", "vergeben"].contains($0.status) }
            .reduce(0) { $0 + ($1.preis ?? 0) }
    }
    private var sortedFiltered: [GGeschenk] {
        geschenke
            .filter { filterStatus == nil || $0.status == filterStatus }
            .sorted { ($0.ranking ?? 0) > ($1.ranking ?? 0) }
    }

    var body: some View {
        Group {
            if let e = ereignis {
                if swipeMode {
                    // Bewerten-Modus NICHT in einer ScrollView (sonst kollidiert die Swipe-Geste mit dem Scrollen).
                    VStack(spacing: 12) {
                        giftsHeader(e)
                        GeschenkRateView(
                            geschenke: geschenke,
                            onVote: { g, delta in Task { await vote(g, delta) } },
                            onSchonGeschenkt: { g in Task { await schonGeschenkt(g) } },
                            onExit: { swipeMode = false }
                        )
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.top, 12)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            if e.profilBestaetigungAngefragt && !e.profilBestaetigt { profileBanner(e) }
                            headerCard(e)
                            giftsHeader(e)
                            statusFilter(e)
                            listMode
                        }
                        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 28)
                    }
                }
            } else if loading {
                ProgressView("Lädt …").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AreaEmptyState(emoji: "🎁", title: "Nicht gefunden")
            }
        }
        .accessibilityIdentifier("gp-ereignis-detail")
        .navigationTitle(ereignis.map { "\(GStyle.anlassEmoji($0.anlass)) \($0.kindName ?? "")" } ?? "Ereignis")
        .navigationBarTitleDisplayMode(.inline)
        .background(Palette.gradient(for: "geschenkplaner").opacity(0.05).ignoresSafeArea())
        .task { await load() }
        .sheet(item: $giftSheet) { ref in
            GGiftFormSheet(ereignisID: ereignisID, kindId: ereignis?.kindId ?? 0, gift: ref.gift)
                .environmentObject(store)
                .onDisappear { Task { await load() } }
        }
        .confirmationDialog(deleteTarget.map { "\"\($0.titel)\" löschen?" } ?? "",
                            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let t = deleteTarget { Task { await deleteGift(t) } }
                deleteTarget = nil
            }
            Button("Abbrechen", role: .cancel) { deleteTarget = nil }
        }
        .confirmationDialog("Geschenk als vergeben markieren und ins Archiv übernehmen?",
                            isPresented: Binding(get: { vergebenTarget != nil }, set: { if !$0 { vergebenTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Vergeben", role: .destructive) {
                if let t = vergebenTarget { Task { await vergeben(t) } }
                vergebenTarget = nil
            }
            Button("Abbrechen", role: .cancel) { vergebenTarget = nil }
        }
    }

    // MARK: - Kopf

    private func profileBanner(_ e: GEreignis) -> some View {
        HStack(spacing: 12) {
            Text("⚠️")
            Text("Profil prüfen: Sind \(e.kindName ?? "")s Interessen noch aktuell?").font(.caption)
            Spacer(minLength: 6)
            Button { Task { await confirmProfil(e) } } label: {
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

    private func headerCard(_ e: GEreignis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(GStyle.anlassEmoji(e.anlass)) \(e.kindName ?? "") — \(GStyle.anlassLabel(e.anlass)) \(String(e.jahr))")
                        .font(.headline)
                    Text(headerSub(e)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                GCountdownBadge(datum: e.datum)
            }
            if let bmax = e.budgetMax, bmax > 0 {
                GBudgetBar(ausgaben: ausgaben, budgetMax: Double(bmax))
            }
            if let p = e.profil, !p.isEmpty {
                NoteBlock(icon: "📝", text: p, tint: Color(hex: "F59E0B"))
            }
            Divider()
            HStack {
                Text("🔔 Erinnerungen").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: $reminderOn).labelsHidden().tint(GStyle.accent)
                    .onChange(of: reminderOn) { _, nv in Task { await setReminder(nv) } }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle().fill(GStyle.anlassColor(e.anlass)).frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }

    private func headerSub(_ e: GEreignis) -> String {
        var parts: [String] = ["📅 \(GDate.fmt(e.datum))"]
        if let a = e.alterZumEreignis { parts.append("👶 \(a) Jahre") }
        if let bmax = e.budgetMax {
            parts.append("💰 \(e.budgetMin ?? 0)–\(bmax) € (\(GStyle.eur(ausgaben)) geplant)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Geschenk-Header (Modus-Umschalter)

    private func giftsHeader(_ e: GEreignis) -> some View {
        HStack {
            if swipeMode {
                Text("💘 \(e.kindName ?? "") — \(GStyle.anlassLabel(e.anlass))").font(.subheadline.weight(.bold))
                Spacer()
                Button { swipeMode = false } label: { pill("📋 Liste", Color(hex: "EC4899"), filled: true) }
                    .buttonStyle(.plain)
            } else {
                Text("🎁 Geschenke (\(geschenke.count))").font(.subheadline.weight(.bold))
                Spacer()
                Button { swipeMode = true } label: { pill("💘 Bewerten", Color(hex: "EC4899"), filled: false) }
                    .buttonStyle(.plain)
                Button { giftSheet = GiftEditRef(gift: nil) } label: { pill("+ Geschenk", GStyle.accent, filled: true) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func pill(_ text: String, _ color: Color, filled: Bool) -> some View {
        Text(text).font(.caption.weight(.bold))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(filled ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.15)), in: Capsule())
            .foregroundStyle(filled ? color.onFill : color)
    }

    // MARK: - Status-Filter

    @ViewBuilder private func statusFilter(_ e: GEreignis) -> some View {
        if !geschenke.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterPill(label: "Alle (\(geschenke.count))", selected: filterStatus == nil, color: GStyle.accent) {
                        filterStatus = nil
                    }
                    ForEach(GStyle.statuses, id: \.self) { s in
                        let count = geschenke.filter { $0.status == s }.count
                        if count > 0 {
                            FilterPill(label: "\(GStyle.statusLabel(s)) (\(count))",
                                       selected: filterStatus == s,
                                       color: GStyle.statusColor(s)) {
                                filterStatus = (filterStatus == s) ? nil : s
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Listen-Modus

    @ViewBuilder private var listMode: some View {
        if geschenke.isEmpty {
            AreaEmptyState(emoji: "🎁", title: "Noch keine Geschenkideen.", hint: "Füge eine hinzu!")
                .frame(minHeight: 180)
        } else {
            ForEach(sortedFiltered) { g in
                GGiftListCard(
                    g: g,
                    onCycle: { Task { await cycleStatus(g) } },
                    onEdit: { giftSheet = GiftEditRef(gift: g) },
                    onVergeben: { vergebenTarget = g },
                    onSchonGeschenkt: { Task { await schonGeschenkt(g) } },
                    onDelete: { deleteTarget = g }
                )
            }
        }
    }

    // MARK: - Aktionen

    private func load() async {
        loading = true
        if let e = try? await store.api.ereignis(ereignisID) {
            ereignis = e
            reminderOn = e.erinnerungenAktiv != 0
        }
        loading = false
    }

    private func setReminder(_ nv: Bool) async {
        guard let e = ereignis else { return }
        let newVal = nv ? 1 : 0
        if newVal == e.erinnerungenAktiv { return }
        do {
            try await store.api.patchEreignisReminder(e.id, aktiv: newVal)
            store.notify(newVal == 1 ? "Erinnerungen aktiviert 🔔" : "Erinnerungen deaktiviert 🔕")
            await load()
            await store.loadDashboard()
        } catch {
            store.notify(store.errText(error), error: true)
            reminderOn = e.erinnerungenAktiv != 0
        }
    }

    private func confirmProfil(_ e: GEreignis) async {
        do {
            try await store.api.confirmProfil(e.kindId)
            store.notify("Profil bestätigt ✅")
            await load()
            await store.loadDashboard()
        } catch { store.notify(store.errText(error), error: true) }
    }

    private func cycleStatus(_ g: GGeschenk) async {
        let idx = GStyle.statuses.firstIndex(of: g.status) ?? 0
        let next = GStyle.statuses[(idx + 1) % (GStyle.statuses.count - 1)] // ueberspringt vergeben
        do {
            try await store.api.updateGeschenk(g.id, ["status": next])
            store.notify("Status → \(GStyle.statusLabel(next))")
            await load()
            await store.loadDashboard(); await store.loadEinkauf()
        } catch { store.notify(store.errText(error), error: true) }
    }

    private func vergeben(_ g: GGeschenk) async {
        do {
            try await store.api.vergeben(g.id)
            store.notify("Vergeben & archiviert 🎉")
            await load()
            await store.loadDashboard(); await store.loadEinkauf()
        } catch { store.notify(store.errText(error), error: true) }
    }

    private func schonGeschenkt(_ g: GGeschenk) async {
        do {
            try await store.api.schonGeschenkt(g.id)
            store.notify("Als schon geschenkt markiert & entfernt 🔄")
            await load()
            await store.loadDashboard(); await store.loadEinkauf()
        } catch { store.notify(store.errText(error), error: true) }
    }

    private func deleteGift(_ g: GGeschenk) async {
        do {
            try await store.api.deleteGeschenk(g.id)
            store.notify("Gelöscht")
            await load()
            await store.loadDashboard(); await store.loadEinkauf()
        } catch { store.notify(store.errText(error), error: true) }
    }

    private func vote(_ g: GGeschenk, _ delta: Int) async {
        let newRanking = (g.ranking ?? 0) + delta
        do {
            try await store.api.updateGeschenk(g.id, ["ranking": newRanking])
            await load()
        } catch { store.notify(store.errText(error), error: true) }
    }
}

// MARK: - Geschenk-Karte (Listen-Modus)

struct GGiftListCard: View {
    let g: GGeschenk
    var onCycle: () -> Void
    var onEdit: () -> Void
    var onVergeben: () -> Void
    var onSchonGeschenkt: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let path = g.imagePath {
                AuthImage(path: path, contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    GRankingBadge(ranking: g.ranking)
                    Text(g.titel).font(.subheadline.weight(.bold))
                        .strikethrough(g.status == "vergeben")
                        .foregroundStyle(g.status == "vergeben" ? .secondary : .primary)
                    GStatusChip(status: g.status, tappable: true, onTap: onCycle)
                }
                GGiftMetaChips(g: g)
                if let b = g.begruendung, !b.isEmpty {
                    NoteBlock(icon: "💡", text: b, tint: Color(hex: "F59E0B"))
                }
                if let d = g.beschreibung, !d.isEmpty { Text(d).font(.caption).foregroundStyle(.secondary) }
                if let n = g.notizen, !n.isEmpty { Text(n).font(.caption).italic().foregroundStyle(.secondary) }
            }
            Spacer(minLength: 4)
            VStack(spacing: 6) {
                iconButton("✏️", onEdit)
                if g.status != "vergeben" { iconButton("🎉", onVergeben) }
                if g.status == "vorschlag" { iconButton("🔄", onSchonGeschenkt) }
                iconButton("🗑️", onDelete)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func iconButton(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
