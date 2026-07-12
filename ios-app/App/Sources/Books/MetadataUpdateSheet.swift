import SwiftUI

/// Metadaten aktualisieren (spec §7.2): editierbare Suchparameter (Titel/Autor/ISBN),
/// Metadatensuche über `store.api.searchMetadata`, auswählbare Ergebnis-Karten und
/// feldweises Zusammenführen der gewählten Metadaten in eine Kopie des Buchs.
struct MetadataUpdateSheet: View {
    let book: Book
    let onApply: (Book) -> Void

    @EnvironmentObject private var store: BooksStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var author: String
    @State private var isbn: String
    @State private var results: [BookSearchResult] = []
    @State private var selected: BookSearchResult?
    @State private var loading = false
    @State private var searched = false

    init(book: Book, onApply: @escaping (Book) -> Void) {
        self.book = book
        self.onApply = onApply
        _title = State(initialValue: book.title)
        _author = State(initialValue: book.authors.joined(separator: ", "))
        _isbn = State(initialValue: book.isbn ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Suchparameter") {
                    TextField("Titel", text: $title)
                    TextField("Autor", text: $author)
                    TextField("ISBN", text: $isbn).keyboardType(.numbersAndPunctuation)
                    Button { search() } label: { Label("Metadaten suchen", systemImage: "magnifyingglass") }
                        .disabled(loading || (title.trimmingCharacters(in: .whitespaces).isEmpty && isbn.trimmingCharacters(in: .whitespaces).isEmpty))
                }

                if loading {
                    Section {
                        HStack(spacing: 10) { ProgressView(); Text("Suche läuft …") }.foregroundStyle(.secondary)
                    }
                } else if searched && results.isEmpty {
                    Section {
                        ContentUnavailableView("Keine Metadaten gefunden", systemImage: "book",
                                               description: Text("Passen Sie Titel, Autor oder ISBN an."))
                    }
                } else if !results.isEmpty {
                    Section("Ergebnisse (\(results.count))") {
                        ForEach(results) { r in
                            resultCard(r)
                                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        }
                    }
                }
            }
            .navigationTitle("Metadaten aktualisieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                if !results.isEmpty {
                    Button { apply() } label: { Text("Ausgewählte Metadaten anwenden") }
                        .buttonStyle(ElisButtonStyle(enabled: selected != nil))
                        .disabled(selected == nil)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.bar)
                }
            }
        }
    }

    // ── Ergebnis-Karte (auswählbar, Amber-Rahmen bei Auswahl) ──
    private func resultCard(_ r: BookSearchResult) -> some View {
        let isSel = selected?.id == r.id
        return HStack(alignment: .top, spacing: 12) {
            BookCover(url: r.thumbnail).frame(width: 60)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(r.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Spacer(minLength: 6)
                    sourceBadge(r.source)
                }
                Text(r.authorText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let p = r.publisher, !p.isEmpty { Text(p).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                if let d = r.publishedDate, !d.isEmpty { Text(d).font(.caption2).foregroundStyle(.secondary) }
                if !r.categories.isEmpty { CategoryPills(categories: r.categories, limit: 4) }
            }
        }
        .padding(8)
        .background(isSel ? BookTheme.amber700.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSel ? BookTheme.amber700 : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { selected = isSel ? nil : r }
    }

    private func sourceBadge(_ source: String) -> some View {
        let name: String
        switch source {
        case "google": name = "Google Books"
        case "openlibrary": name = "Open Library"
        case "worldcat": name = "WorldCat"
        case "isbndb": name = "ISBNdb"
        case "canopy", "amazon": name = "Amazon.de"
        default: name = source.capitalized
        }
        return Text(name).font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Color.blue.opacity(0.15), in: Capsule())
            .foregroundStyle(.blue)
    }

    // ── Aktionen ──
    private func search() {
        let isbnTrim = isbn.trimmingCharacters(in: .whitespaces)
        let query = isbnTrim.isEmpty ? title.trimmingCharacters(in: .whitespaces) : "isbn:\(isbnTrim)"
        let authorArg = isbnTrim.isEmpty ? author.trimmingCharacters(in: .whitespaces) : ""
        loading = true
        searched = true
        selected = nil
        Task {
            let r = (try? await store.api.searchMetadata(query: query, author: authorArg)) ?? []
            results = r
            loading = false
        }
    }

    private func apply() {
        guard let r = selected else { return }
        var merged = book
        if !r.title.isEmpty { merged.title = r.title }
        if !r.authors.isEmpty { merged.authors = r.authors }
        if let p = r.publisher, !p.isEmpty { merged.publisher = p }
        if let d = r.publishedDate, !d.isEmpty { merged.publishedDate = d }
        if let d = r.description, !d.isEmpty { merged.description = d }
        if let pc = r.pageCount, pc > 0 { merged.pageCount = pc }
        if !r.categories.isEmpty { merged.categories = r.categories }
        if let t = r.thumbnail, !t.isEmpty { merged.thumbnail = t }
        if let i = r.isbn, !i.isEmpty { merged.isbn = i }
        Task {
            await store.updateBookFields(book.id, merged.apiFields())
            onApply(merged)
            dismiss()
        }
    }
}
