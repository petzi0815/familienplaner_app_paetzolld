import SwiftUI

/// Ressourcenübergreifende Live-Suche — nach Lebensbereichen gruppiert, Backend ist tippfehlertolerant.
struct SearchView: View {
    @EnvironmentObject private var app: AppState
    @State private var query = ""
    @State private var results: [SearchHit] = []
    @State private var busy = false
    @State private var searched = false

    var body: some View {
        NavigationStack {
            Group {
                if busy && results.isEmpty {
                    ProgressView().padding(.top, 60)
                } else if results.isEmpty && searched {
                    ContentUnavailableView.search(text: query)
                } else if results.isEmpty {
                    ContentUnavailableView {
                        Label("Alles durchsuchen", systemImage: "sparkle.magnifyingglass")
                    } description: {
                        Text("Termine, Reisen, Bücher, Vorräte – ein Suchfeld für alle Lebensbereiche. Tippfehler sind ok.")
                    }
                } else {
                    List {
                        ForEach(groups) { g in
                            Section {
                                ForEach(g.hits) { hit in resultRow(hit) }
                            } header: {
                                Text("\(g.emoji)  \(g.title)  ·  \(g.hits.count)")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Suchen")
            .searchable(text: $query, prompt: "Termine, Bücher, Vorräte …")
            .task(id: query) { await liveSearch() }
            .task { await app.loadCapabilities() }
        }
    }

    // ── Nach Lebensbereich gruppiert (Reihenfolge wie im Katalog) ──
    private struct SearchGroup: Identifiable {
        let domain: String, title: String, emoji: String
        let hits: [SearchHit]
        var id: String { domain }
    }
    private var groups: [SearchGroup] {
        let byDomain = Dictionary(grouping: results, by: { $0.domain })
        let order = DomainCatalog.order + byDomain.keys.filter { !DomainCatalog.order.contains($0) }.sorted()
        return order.compactMap { d in
            guard let hits = byDomain[d], !hits.isEmpty else { return nil }
            let m = DomainCatalog.meta[d]
            return SearchGroup(domain: d, title: m?.title ?? (hits.first?.label ?? d), emoji: m?.emoji ?? "🔎", hits: hits)
        }
    }

    @ViewBuilder private func resultRow(_ hit: SearchHit) -> some View {
        if let res = app.resources.first(where: { $0.key == hit.resource }) {
            NavigationLink { RecordLoaderView(resource: res, id: hit.entityId.value) } label: { rowContent(hit) }
        } else {
            rowContent(hit)
        }
    }

    private func rowContent(_ hit: SearchHit) -> some View {
        HStack(spacing: 12) {
            GradientIcon(systemName: icon(for: hit.domain), gradientKey: hit.domain, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.display.isEmpty ? "(ohne Titel)" : hit.display)
                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(hit.label).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func liveSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { results = []; searched = false; return }
        try? await Task.sleep(nanoseconds: 300_000_000) // Debounce; bricht ab, wenn weitergetippt wird
        if Task.isCancelled { return }
        busy = true
        defer { busy = false }
        searched = true
        results = (try? await app.api.search(q))?.results ?? []
    }

    private func icon(for domain: String) -> String {
        switch domain {
        case "termine": return "calendar"
        case "reisen": return "airplane"
        case "elisbooks", "ebooks": return "book.fill"
        case "vorratskammer": return "fork.knife"
        case "geschenkplaner", "wunschliste": return "gift.fill"
        case "garten": return "leaf.fill"
        case "samu": return "teddybear.fill"
        case "gypsi": return "pawprint.fill"
        case "smarthome": return "house.fill"
        case "vertraege": return "doc.text.fill"
        case "reiniger": return "sparkles"
        case "foto": return "photo.fill"
        default: return "square.grid.2x2.fill"
        }
    }
}
