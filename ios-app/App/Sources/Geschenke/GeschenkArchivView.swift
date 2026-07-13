import SwiftUI

/// Archiv-Tab: vergangene Geschenke (Kind-Filter) + Eintragen + Loeschen.
struct GeschenkArchivView: View {
    @EnvironmentObject private var store: GeschenkStore
    @State private var filterKindId: Int? = nil
    @State private var showAdd = false
    @State private var deleteTarget: GVergangenes?

    private var filtered: [GVergangenes] {
        guard let f = filterKindId else { return store.archivVergangene }
        return store.archivVergangene.filter { $0.kindId == f }
    }

    var body: some View {
        ScrollView {
            if store.loadingArchiv && store.archivVergangene.isEmpty && store.archivKinder.isEmpty {
                ProgressView("Lädt …").frame(maxWidth: .infinity, minHeight: 240)
            } else {
                VStack(spacing: 12) {
                    header
                    filterMenu
                    if filtered.isEmpty {
                        AreaEmptyState(emoji: "📦", title: "Noch keine vergangenen Geschenke.").frame(minHeight: 200)
                    } else {
                        ForEach(filtered) { v in card(v) }
                    }
                }
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 28)
            }
        }
        .task { await store.loadArchiv() }
        .refreshable { await store.loadArchiv() }
        .sheet(isPresented: $showAdd) {
            GPastGiftSheet(kinder: store.archivKinder).environmentObject(store)
        }
        .confirmationDialog("Wirklich löschen?",
                            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let t = deleteTarget { Task { await store.deleteVergangenes(t.id) } }
                deleteTarget = nil
            }
            Button("Abbrechen", role: .cancel) { deleteTarget = nil }
        }
    }

    private var header: some View {
        HStack {
            Text("📦 Vergangene Geschenke (\(filtered.count))").font(.subheadline.weight(.bold))
            Spacer()
            Button { showAdd = true } label: {
                Label("Hinzufügen", systemImage: "plus.circle.fill").font(.subheadline.weight(.semibold))
            }
            .disabled(store.archivKinder.isEmpty)
        }
    }

    private var filterMenu: some View {
        HStack {
            Menu {
                Button("Alle Kinder") { filterKindId = nil }
                ForEach(store.archivKinder) { k in
                    Button(k.name) { filterKindId = k.id }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(filterKindId.flatMap { id in store.archivKinder.first { $0.id == id }?.name } ?? "Alle Kinder").lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color(.secondarySystemBackground), in: Capsule())
                .foregroundStyle(.primary)
            }
            Spacer()
        }
    }

    private func card(_ v: GVergangenes) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(v.titel).font(.subheadline.weight(.bold))
                Text(sub(v)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Button { deleteTarget = v } label: {
                Text("🗑️").font(.footnote)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sub(_ v: GVergangenes) -> String {
        var parts: [String] = ["👶 \(v.kindName ?? "")"]
        if let a = v.anlass { parts.append("\(GStyle.anlassEmoji(a)) \(GStyle.anlassLabel(a))") }
        if let j = v.jahr { parts.append("\(j)") }
        if let n = v.notizen, !n.isEmpty { parts.append(n) }
        return parts.joined(separator: " · ")
    }
}
