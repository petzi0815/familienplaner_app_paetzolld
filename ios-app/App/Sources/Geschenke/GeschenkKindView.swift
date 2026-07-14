import SwiftUI

/// Kind-Detail (gepusht): Profil/Negativliste, Anlass-Konfiguration, Ereignisse, vergangene Geschenke.
struct GeschenkKindView: View {
    let kindID: Int
    @EnvironmentObject private var store: GeschenkStore

    @State private var kind: GKind?
    @State private var ereignisse: [GEreignis] = []
    @State private var vergangene: [GVergangenes] = []
    @State private var loading = true

    @State private var fProfil = ""
    @State private var fNegativ = ""

    struct AnlassEntry: Equatable { var aktiv: Bool; var min: String; var max: String }
    @State private var anlassState: [String: AnlassEntry] = [:]

    @State private var deleteTarget: GVergangenes?

    var body: some View {
        Group {
            if let k = kind {
                ScrollView {
                    VStack(spacing: 12) {
                        profileCard(k)
                        anlassCard
                        ereignisseCard
                        vergangeneCard
                    }
                    .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 28)
                }
            } else if loading {
                ProgressView("Lädt …").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AreaEmptyState(emoji: "👶", title: "Nicht gefunden")
            }
        }
        .navigationTitle(kind.map { "👶 \($0.name)" } ?? "Kind")
        .navigationBarTitleDisplayMode(.inline)
        .background(Palette.gradient(for: "geschenkplaner").opacity(0.05).ignoresSafeArea())
        .task { await load() }
        .confirmationDialog("Wirklich löschen?",
                            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let t = deleteTarget { Task { await deleteVergangenes(t) } }
                deleteTarget = nil
            }
            Button("Abbrechen", role: .cancel) { deleteTarget = nil }
        }
    }

    // MARK: - Profil

    private func profileCard(_ k: GKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text("👶 \(k.name)").font(.headline)
                if let a = k.alter { Text("(\(a) Jahre)").font(.subheadline).foregroundStyle(.secondary) }
            }
            Text(profileSub(k)).font(.caption).foregroundStyle(.secondary)

            Text("Profil (Interessen, Hobbys)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            TextField("Interessen, Hobbys …", text: $fProfil, axis: .vertical)
                .lineLimit(3...6).textFieldStyle(.roundedBorder)

            Text("🚫 Negativliste (was NICHT vorgeschlagen werden soll)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            TextField("z.B. Kleidung, Süßigkeiten, Videospiele …", text: $fNegativ, axis: .vertical)
                .lineLimit(2...5).textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                Button { Task { await saveProfil() } } label: {
                    smallButton("💾 Speichern", GStyle.accent)
                }.buttonStyle(.plain)
                Button { Task { await confirmProfil() } } label: {
                    smallButton("✅ Bestätigen", Color(hex: "10B981"))
                }.buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func profileSub(_ k: GKind) -> String {
        var s = k.geburtsdatum.map { "📅 \(GDate.fmt($0))" } ?? "📅 Kein Geburtsdatum"
        if let b = k.profilBestaetigtAm { s += " · Profil bestätigt: \(GDate.fmt(b))" }
        return s
    }

    // MARK: - Anlass-Konfiguration

    private var anlassCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("⚙️ Anlass-Konfiguration").font(.subheadline.weight(.bold))
            ForEach(GStyle.anlassOrder, id: \.self) { a in
                HStack(spacing: 10) {
                    Toggle("", isOn: Binding(
                        get: { anlassState[a]?.aktiv ?? false },
                        set: { nv in setAnlass(a) { $0.aktiv = nv } }
                    ))
                    .labelsHidden().tint(GStyle.accent).fixedSize()
                    Text("\(GStyle.anlassEmoji(a)) \(GStyle.anlassLabel(a))").font(.subheadline)
                        .frame(width: 130, alignment: .leading)
                    TextField("Min", text: Binding(
                        get: { anlassState[a]?.min ?? "" },
                        set: { nv in setAnlass(a) { $0.min = nv } }
                    ))
                    .keyboardType(.numberPad).multilineTextAlignment(.center)
                    .frame(width: 52).padding(.vertical, 5)
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    Text("–").font(.caption).foregroundStyle(.secondary)
                    TextField("Max", text: Binding(
                        get: { anlassState[a]?.max ?? "" },
                        set: { nv in setAnlass(a) { $0.max = nv } }
                    ))
                    .keyboardType(.numberPad).multilineTextAlignment(.center)
                    .frame(width: 52).padding(.vertical, 5)
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    Spacer(minLength: 0)
                }
                if a != GStyle.anlassOrder.last { Divider() }
            }
            Button { Task { await saveAnlaesse() } } label: {
                smallButton("💾 Speichern", GStyle.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Ereignisse

    private var ereignisseCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📅 Ereignisse").font(.subheadline.weight(.bold))
            if ereignisse.isEmpty {
                Text("Ereignisse werden automatisch angelegt.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(ereignisse) { e in
                    NavigationLink { GeschenkEreignisView(ereignisID: e.id).environmentObject(store) } label: {
                        HStack(spacing: 10) {
                            Text(GStyle.anlassEmoji(e.anlass)).font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(GStyle.anlassLabel(e.anlass)) \(String(e.jahr))").font(.subheadline.weight(.semibold))
                                Text(ereignisSub(e)).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 6)
                            let cd = GDate.countdown(e.datum)
                            Text(cd.text).font(.caption.weight(.bold))
                                .foregroundStyle(cd.soon ? Color.red : .secondary)
                        }
                        .foregroundStyle(.primary)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if e.id != ereignisse.last?.id { Divider() }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func ereignisSub(_ e: GEreignis) -> String {
        var parts: [String] = [GDate.fmt(e.datum)]
        if let a = e.alterZumEreignis { parts.append("\(a) Jahre") }
        parts.append("\(e.geschenke.count) Geschenke")
        return parts.joined(separator: " · ")
    }

    // MARK: - Vergangene Geschenke

    private var vergangeneCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📦 Vergangene Geschenke").font(.subheadline.weight(.bold))
            if vergangene.isEmpty {
                Text("Noch keine vergangenen Geschenke.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(vergangene) { v in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(v.titel).font(.subheadline.weight(.medium))
                            Text(vergangenSub(v)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        Button { deleteTarget = v } label: {
                            Text("🗑️").font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                    if v.id != vergangene.last?.id { Divider() }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func vergangenSub(_ v: GVergangenes) -> String {
        var parts: [String] = []
        if let a = v.anlass { parts.append("\(GStyle.anlassEmoji(a)) \(GStyle.anlassLabel(a))") }
        if let j = v.jahr { parts.append("\(j)") }
        return parts.joined(separator: " · ")
    }

    private func smallButton(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption.weight(.bold))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(color, in: Capsule())
            .foregroundStyle(color.onFill)
    }

    // MARK: - Laden & Aktionen

    private func setAnlass(_ a: String, _ mutate: (inout AnlassEntry) -> Void) {
        var e = anlassState[a] ?? AnlassEntry(aktiv: false, min: "", max: "")
        mutate(&e)
        anlassState[a] = e
    }

    private func load() async {
        loading = true
        async let k = store.api.kind(kindID)
        async let anl = store.api.anlaesse(kindID)
        async let erg = store.api.ereignisse(kindId: kindID)
        async let verg = store.api.vergangene(kindId: kindID)
        let loadedKind = try? await k
        let loadedAnl = (try? await anl) ?? []
        ereignisse = (try? await erg) ?? []
        vergangene = (try? await verg) ?? []
        if let loadedKind {
            kind = loadedKind
            fProfil = loadedKind.profil ?? ""
            fNegativ = loadedKind.negativliste ?? ""
        }
        var state: [String: AnlassEntry] = [:]
        for a in GStyle.anlassOrder {
            let cfg = loadedAnl.first { $0.anlass == a }
            state[a] = AnlassEntry(
                aktiv: cfg?.aktiv ?? false,
                min: cfg?.budgetMin.map(String.init) ?? "",
                max: cfg?.budgetMax.map(String.init) ?? ""
            )
        }
        anlassState = state
        loading = false
    }

    private func saveProfil() async {
        do {
            try await store.api.updateKind(kindID, [
                "profil": fProfil,
                "negativliste": fNegativ.isEmpty ? NSNull() : fNegativ,
            ])
            store.notify("Profil gespeichert ✅")
            await store.loadKinder()
        } catch { store.notify(store.err(error), error: true) }
    }

    private func confirmProfil() async {
        do {
            try await store.api.confirmProfil(kindID)
            store.notify("Profil bestätigt ✅")
            await load()
            await store.loadKinder(); await store.loadDashboard()
        } catch { store.notify(store.err(error), error: true) }
    }

    private func saveAnlaesse() async {
        let configs = GStyle.anlassOrder.map { a -> [String: Any] in
            let e = anlassState[a]
            return [
                "anlass": a,
                "aktiv": (e?.aktiv ?? false) ? 1 : 0,
                "budget_min": e.flatMap { Int($0.min) }.map { $0 as Any } ?? NSNull(),
                "budget_max": e.flatMap { Int($0.max) }.map { $0 as Any } ?? NSNull(),
            ]
        }
        do {
            _ = try await store.api.putAnlaesse(kindID, configs: configs)
            store.notify("Anlass-Konfiguration gespeichert ✅")
            await store.loadKinder()
        } catch { store.notify(store.err(error), error: true) }
    }

    private func deleteVergangenes(_ v: GVergangenes) async {
        do {
            try await store.api.deleteVergangenes(v.id)
            store.notify("Gelöscht")
            await load()
            await store.loadArchiv()
        } catch { store.notify(store.err(error), error: true) }
    }
}
