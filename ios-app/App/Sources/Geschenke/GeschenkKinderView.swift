import SwiftUI

/// Kinder-Tab: Kinder-Liste (+ Anlagen), Budget-Matrix (Kinder × Anlaesse).
struct GeschenkKinderView: View {
    @EnvironmentObject private var store: GeschenkStore
    @State private var showAdd = false
    @State private var deleteTarget: GKind?

    // Matrix-Zustand (lokal, wird beim Speichern gebuendelt geschrieben)
    struct MatrixEntry: Equatable { var aktiv: Bool; var min: String; var max: String }
    @State private var matrix: [String: MatrixEntry] = [:]
    @State private var matrixDirty = false

    private func key(_ kindId: Int, _ anlass: String) -> String { "\(kindId)_\(anlass)" }

    var body: some View {
        ScrollView {
            if store.loadingKinder && store.kinder.isEmpty {
                ProgressView("Lädt …").frame(maxWidth: .infinity, minHeight: 240)
            } else {
                VStack(spacing: 12) {
                    header
                    if store.kinder.isEmpty {
                        AreaEmptyState(emoji: "👶", title: "Noch keine Kinder angelegt.").frame(minHeight: 200)
                    } else {
                        ForEach(store.kinder) { k in childCard(k) }
                        matrixCard
                    }
                }
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 28)
            }
        }
        .task { await store.loadKinder() }
        .refreshable { await store.loadKinder() }
        .onChange(of: store.kinder) { _, _ in rebuildMatrix() }
        .onAppear { rebuildMatrix() }
        .sheet(isPresented: $showAdd) {
            GChildCreateSheet().environmentObject(store)
        }
        .confirmationDialog(deleteTarget.map { "\"\($0.name)\" wirklich löschen? Alle Ereignisse und Geschenke werden gelöscht!" } ?? "",
                            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let t = deleteTarget { Task { await store.deleteKind(t) } }
                deleteTarget = nil
            }
            Button("Abbrechen", role: .cancel) { deleteTarget = nil }
        }
    }

    private var header: some View {
        HStack {
            Text("👶 Kinder (\(store.kinder.count))").font(.subheadline.weight(.bold))
            Spacer()
            Button { showAdd = true } label: {
                Label("Hinzufügen", systemImage: "plus.circle.fill").font(.subheadline.weight(.semibold))
            }
        }
    }

    // MARK: - Kind-Karte

    private func childCard(_ k: GKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                NavigationLink(value: GeschenkRoute.kind(k.id)) { childInfo(k) }
                    .buttonStyle(.plain)
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    NavigationLink(value: GeschenkRoute.kind(k.id)) { smallTag("✏️") }
                        .buttonStyle(.plain)
                    Button { deleteTarget = k } label: { smallTag("🗑️") }
                        .buttonStyle(.plain)
                }
            }
            if !k.anlaesse.isEmpty { GAnlassChips(anlaesse: k.anlaesse) }
            if !k.naechsteEreignisse.isEmpty {
                Divider()
                ForEach(k.naechsteEreignisse) { e in
                    NavigationLink(value: GeschenkRoute.ereignis(e.id)) {
                        HStack(spacing: 8) {
                            Text(GStyle.anlassEmoji(e.anlass))
                            Text("\(GStyle.anlassLabel(e.anlass)) \(e.jahr)").font(.caption)
                            Spacer(minLength: 6)
                            let cd = GDate.countdown(e.datum)
                            Text(cd.text).font(.caption.weight(.bold))
                                .foregroundStyle(cd.soon ? Color.red : .secondary)
                        }
                        .foregroundStyle(.primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func childInfo(_ k: GKind) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("👶 \(k.name)").font(.subheadline.weight(.bold))
                if let a = k.alter { Text("(\(a) Jahre)").font(.subheadline).foregroundStyle(.secondary) }
            }
            if let g = k.geburtsdatum { Text("📅 \(GDate.fmt(g))").font(.caption).foregroundStyle(.secondary) }
            if let p = k.profil, !p.isEmpty { Text(p).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            if let n = k.negativliste, !n.isEmpty { Text("🚫 \(n)").font(.caption2).foregroundStyle(.red) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func smallTag(_ t: String) -> some View {
        Text(t).font(.footnote)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Budget-Matrix

    private var matrixCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("⚙️ Budget-Matrix").font(.subheadline.weight(.bold))
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .center, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        Text("Kind").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        ForEach(GStyle.anlassOrder, id: \.self) { a in
                            VStack(spacing: 1) {
                                Text(GStyle.anlassEmoji(a)).font(.body)
                                Text(GStyle.anlassLabel(a)).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(width: 128)
                        }
                    }
                    ForEach(store.kinder) { k in
                        GridRow {
                            Text(k.name).font(.caption.weight(.semibold))
                                .frame(width: 80, alignment: .leading)
                            ForEach(GStyle.anlassOrder, id: \.self) { a in
                                matrixCell(k, a).frame(width: 128)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            if matrixDirty {
                Button { Task { await saveMatrix() } } label: {
                    Text("💾 Alles speichern").font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(GStyle.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(GStyle.accent.onFill)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func matrixCell(_ k: GKind, _ anlass: String) -> some View {
        let ky = key(k.id, anlass)
        let noDate = anlass == "geburtstag" && (k.geburtsdatum == nil)
        let entry = matrix[ky] ?? MatrixEntry(aktiv: false, min: "", max: "")
        return VStack(spacing: 6) {
            Toggle("", isOn: Binding(
                get: { matrix[ky]?.aktiv ?? false },
                set: { nv in setCell(ky) { $0.aktiv = nv } }
            ))
            .labelsHidden()
            .tint(GStyle.accent)
            .disabled(noDate)
            .opacity(noDate ? 0.3 : 1)
            if entry.aktiv && !noDate {
                HStack(spacing: 4) {
                    TextField("Min", text: Binding(
                        get: { matrix[ky]?.min ?? "" },
                        set: { nv in setCell(ky) { $0.min = nv } }
                    ))
                    .keyboardType(.numberPad).multilineTextAlignment(.center)
                    .frame(width: 46).padding(.vertical, 4)
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    Text("–").font(.caption2).foregroundStyle(.secondary)
                    TextField("Max", text: Binding(
                        get: { matrix[ky]?.max ?? "" },
                        set: { nv in setCell(ky) { $0.max = nv } }
                    ))
                    .keyboardType(.numberPad).multilineTextAlignment(.center)
                    .frame(width: 46).padding(.vertical, 4)
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func setCell(_ ky: String, _ mutate: (inout MatrixEntry) -> Void) {
        var e = matrix[ky] ?? MatrixEntry(aktiv: false, min: "", max: "")
        mutate(&e)
        matrix[ky] = e
        matrixDirty = true
    }

    private func rebuildMatrix() {
        var m: [String: MatrixEntry] = [:]
        for k in store.kinder {
            for a in GStyle.anlassOrder {
                let cfg = k.anlaesse.first { $0.anlass == a }
                let noDate = a == "geburtstag" && (k.geburtsdatum == nil)
                m[key(k.id, a)] = MatrixEntry(
                    aktiv: !noDate && (cfg?.aktiv ?? false),
                    min: cfg?.budgetMin.map(String.init) ?? "",
                    max: cfg?.budgetMax.map(String.init) ?? ""
                )
            }
        }
        matrix = m
        matrixDirty = false
    }

    private func saveMatrix() async {
        var byKind: [Int: [[String: Any]]] = [:]
        for k in store.kinder {
            byKind[k.id] = GStyle.anlassOrder.map { a -> [String: Any] in
                let e = matrix[key(k.id, a)]
                return [
                    "anlass": a,
                    "aktiv": (e?.aktiv ?? false) ? 1 : 0,
                    "budget_min": e.flatMap { Int($0.min) }.map { $0 as Any } ?? NSNull(),
                    "budget_max": e.flatMap { Int($0.max) }.map { $0 as Any } ?? NSNull(),
                ]
            }
        }
        await store.saveMatrix(byKind)
        matrixDirty = false
    }
}
