import SwiftUI

/// Wunschliste (§10): Raster der Wunsch-Bücher mit Regal-Umzug, Rebuy-Suche und Entfernen.
/// Manuell hinzufügen = Metadaten-Suche (Google/Open Library) oder ohne Metadaten.
struct WishlistView: View {
    @EnvironmentObject private var store: BooksStore
    @State private var showManual = false
    private let cols = [GridItem(.adaptive(minimum: 260), spacing: 12)]

    var body: some View {
        ScrollView {
            HStack {
                Label("Wunschliste (\(store.wishlist.count))", systemImage: "heart")
                    .font(.title2.weight(.bold)).labelStyle(.titleAndIcon)
                Spacer()
                Button { showManual = true } label: { Label("Manuell hinzufügen", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).tint(BookTheme.amber700)
            }
            .padding(.horizontal).padding(.top, 8)

            if store.wishlist.isEmpty {
                ContentUnavailableView("Ihre Wunschliste ist leer", systemImage: "heart",
                                       description: Text("Fügen Sie Bücher über die Suchfunktion hinzu."))
                    .padding(.top, 40)
            } else {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(store.wishlist) { item in WishlistCard(item: item) }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showManual) { WishlistManualAddSheet() }
    }
}

/// Eine Wunschlisten-Karte mit eigenem Regal-Picker-Zustand.
private struct WishlistCard: View {
    @EnvironmentObject private var store: BooksStore
    @Environment(\.openURL) private var openURL
    let item: WishlistItem
    @State private var shelfId: String = ""

    private var rebuyURL: URL? {
        let q = "\(item.title) \(item.authorText)"
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.rebuy.de/kaufen/suchen?q=\(enc)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                BookCover(url: item.thumbnail, wishlist: true).frame(width: 74)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(3)
                    Text(item.authorText).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    if let p = item.publisher, !p.isEmpty {
                        Text(p).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            if !item.categories.isEmpty { CategoryPills(categories: item.categories) }

            Divider()

            if store.shelves.isEmpty {
                Text("Kein Regal vorhanden").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Picker("Regal", selection: $shelfId) {
                        ForEach(store.shelves) { s in Text(s.name).tag(s.id) }
                    }
                    .pickerStyle(.menu).labelsHidden()
                    Spacer()
                    Button {
                        Task { await store.moveWishlistToShelf(item, shelfId: shelfId) }
                    } label: { Label("Zu Regal hinzufügen", systemImage: "plus") }
                        .font(.caption.weight(.semibold))
                        .disabled(shelfId.isEmpty)
                }
            }

            HStack(spacing: 10) {
                Button {
                    if let u = rebuyURL { openURL(u) }
                } label: { Label("Rebuy", systemImage: "cart") }
                    .font(.caption.weight(.semibold)).tint(BookTheme.orange600)
                    .disabled(rebuyURL == nil)
                Spacer()
                Button(role: .destructive) {
                    Task { await store.removeWishlist(item.id) }
                } label: { Label("Entfernen", systemImage: "trash") }
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(BookTheme.amber700.opacity(0.18)))
        .onAppear { if shelfId.isEmpty { shelfId = store.activeShelf ?? store.shelves.first?.id ?? "" } }
    }
}

/// Manuell hinzufügen: Titel*/Autor → Metadaten-Suche, ein Ergebnis wählen ODER ohne Metadaten.
private struct WishlistManualAddSheet: View {
    @EnvironmentObject private var store: BooksStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var author = ""
    @State private var results: [BookSearchResult] = []
    @State private var searching = false
    @State private var searched = false

    private var canSearch: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Buch suchen") {
                    TextField("Titel*", text: $title)
                    TextField("Autor (optional)", text: $author)
                    Button {
                        runSearch()
                    } label: {
                        HStack {
                            if searching { ProgressView() } else { Image(systemName: "magnifyingglass") }
                            Text(searching ? "Suchen …" : "Bücher suchen")
                        }
                    }
                    .disabled(!canSearch || searching)
                    Button {
                        addBare()
                    } label: { Label("Ohne Metadaten hinzufügen", systemImage: "plus.circle") }
                        .disabled(!canSearch || searching)
                }

                if searched && results.isEmpty && !searching {
                    Section { Text("Keine Ergebnisse gefunden.").font(.subheadline).foregroundStyle(.secondary) }
                }

                if !results.isEmpty {
                    Section("Ergebnisse (\(results.count))") {
                        ForEach(results) { r in resultRow(r) }
                    }
                }
            }
            .navigationTitle("Zur Wunschliste")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
    }

    private func resultRow(_ r: BookSearchResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            BookCover(url: r.thumbnail).frame(width: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(r.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(r.authorText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let p = r.publisher, !p.isEmpty { Text(p).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                Text(sourceLabel(r.source)).font(.caption2.weight(.medium))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(BookTheme.amber700.opacity(0.14), in: Capsule()).foregroundStyle(BookTheme.amber900)
            }
            Spacer(minLength: 0)
            Button {
                Task { await store.addToWishlist(r, source: r.source); dismiss() }
            } label: { Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(BookTheme.amber700) }
                .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private func runSearch() {
        searching = true; searched = false
        Task {
            let found = (try? await store.api.searchMetadata(query: title, author: author)) ?? []
            results = found
            searching = false; searched = true
        }
    }

    private func addBare() {
        let a = author.trimmingCharacters(in: .whitespaces)
        let r = BookSearchResult(title: title.trimmingCharacters(in: .whitespaces),
                                 authors: a.isEmpty ? [] : [a], publisher: nil, publishedDate: nil,
                                 description: nil, pageCount: nil, categories: [], thumbnail: nil, isbn: nil, source: "manual")
        Task { await store.addToWishlist(r, source: "manual"); dismiss() }
    }

    private func sourceLabel(_ s: String) -> String {
        switch s {
        case "google": return "Google Books"
        case "openlibrary": return "Open Library"
        case "manual": return "Manuell"
        default: return s
        }
    }
}
