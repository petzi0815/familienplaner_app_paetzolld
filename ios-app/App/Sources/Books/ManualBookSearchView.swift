import SwiftUI

/// Manuelle Titel/Autor-Suche (§6.4). Metadaten via `searchMetadata` (Google Books + Open Library),
/// Treffer als Karten → Übernahme ins aktive Regal (`store.activeShelf`).
struct ManualBookSearchView: View {
    @EnvironmentObject private var store: BooksStore

    @State private var title = ""
    @State private var author = ""
    @State private var results: [BookSearchResult] = []
    @State private var searching = false
    @State private var searched = false

    private var hasShelf: Bool { store.activeShelf != nil }
    private var canSearch: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !hasShelf { shelfHint }
                form
                content
            }
            .padding()
        }
    }

    // ── Formular ──
    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Buch manuell hinzufügen").font(.title3.weight(.bold))
            TextField("Titel", text: $title)
                .textFieldStyle(.roundedBorder).submitLabel(.search)
                .onSubmit { if canSearch { search() } }
            TextField("Autor (optional)", text: $author)
                .textFieldStyle(.roundedBorder).submitLabel(.search)
                .onSubmit { if canSearch { search() } }
            HStack {
                Button { search() } label: { Label("Bücher suchen", systemImage: "magnifyingglass") }
                    .buttonStyle(.borderedProminent).tint(BookTheme.amber700)
                    .disabled(!canSearch || searching)
                Button { reset() } label: { Label("Zurücksetzen", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.bordered)
            }
        }
    }

    // ── Inhalt (Laden / leer / Ergebnisse) ──
    @ViewBuilder private var content: some View {
        if searching {
            HStack { ProgressView(); Text("Suche läuft…").foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity).padding(.top, 20)
        } else if searched && results.isEmpty {
            ContentUnavailableView("Keine Ergebnisse", systemImage: "magnifyingglass",
                                   description: Text("Versuchen Sie es mit einem anderen Titel oder Autor."))
                .padding(.top, 20)
        } else {
            ForEach(results) { resultCard($0) }
        }
    }

    private func resultCard(_ r: BookSearchResult) -> some View {
        let src = sourceLabel(r.source)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                BookCover(url: r.thumbnail).frame(width: 80)
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.title).font(.headline).lineLimit(3)
                    Label(r.authorText, systemImage: "person").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let p = r.publisher, !p.isEmpty {
                        Label(p, systemImage: "building.2").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let d = r.publishedDate, !d.isEmpty {
                        Label(d, systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
                    }
                    Label(src.name, systemImage: src.icon)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(BookTheme.amber700.opacity(0.14), in: Capsule())
                        .foregroundStyle(BookTheme.amber900)
                }
                Spacer(minLength: 0)
            }
            Button { add(r) } label: { Label("Hinzufügen", systemImage: "plus") }
                .buttonStyle(ElisButtonStyle(enabled: hasShelf))
                .disabled(!hasShelf)
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(BookTheme.amber700.opacity(0.2)))
    }

    private var shelfHint: some View {
        Label("Kein Regal ausgewählt — bitte oben ein aktives Regal wählen.", systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline).foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // ── Logik ──
    private func search() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let a = author.trimmingCharacters(in: .whitespaces)
        searching = true; searched = false; results = []
        Task {
            let r = (try? await store.api.searchMetadata(query: t, author: a)) ?? []
            results = r
            searching = false
            searched = true
        }
    }

    private func add(_ r: BookSearchResult) {
        guard let shelf = store.activeShelf else { store.notify("Kein Regal ausgewählt", error: true); return }
        Task { _ = await store.addBook(r.toBook(bookshelfId: shelf)) }
    }

    private func reset() { title = ""; author = ""; results = []; searched = false }

    private func sourceLabel(_ s: String) -> (name: String, icon: String) {
        switch s {
        case "google": return ("Google Books", "globe")
        case "openlibrary": return ("Open Library", "book")
        case "worldcat": return ("WorldCat", "cylinder.split.1x2")
        case "isbndb": return ("ISBNdb", "books.vertical")
        case "amazon", "canopy": return ("Amazon.de", "cart")
        default: return (s.capitalized, "tag")
        }
    }
}
