import SwiftUI

/// Ressourcenübergreifende Suche (GET /api/v1/search). Nutzt die iOS-26-Such-Rolle der Tab-Bar.
struct SearchView: View {
    @EnvironmentObject private var app: AppState
    @State private var query = ""
    @State private var results: [SearchHit] = []
    @State private var busy = false
    @State private var searched = false

    var body: some View {
        NavigationStack {
            Group {
                if busy {
                    ProgressView().padding(.top, 80)
                } else if results.isEmpty && searched {
                    ContentUnavailableView.search(text: query)
                } else if results.isEmpty {
                    ContentUnavailableView {
                        Label("Alles durchsuchen", systemImage: "sparkle.magnifyingglass")
                    } description: {
                        Text("Termine, Reisen, Bücher, Vorräte, Geschenke – ein Suchfeld für alle Lebensbereiche.")
                    }
                } else {
                    List(results) { hit in
                        HStack(spacing: 12) {
                            GradientIcon(systemName: icon(for: hit.domain), gradientKey: hit.domain, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.display.isEmpty ? "(ohne Titel)" : hit.display)
                                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(hit.label).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Suchen")
            .searchable(text: $query, prompt: "Termine, Bücher, Vorräte …")
            .onSubmit(of: .search) { Task { await run() } }
            .onChange(of: query) { _, q in if q.isEmpty { results = []; searched = false } }
        }
    }

    private func run() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
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
