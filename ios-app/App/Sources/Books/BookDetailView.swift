import SwiftUI

/// Buch-Detail: Übersicht + Bearbeiten, Lesestatus/Pickliste, Regal verschieben, Löschen, Metadaten aktualisieren.
struct BookDetailView: View {
    @EnvironmentObject private var store: BooksStore
    @Environment(\.dismiss) private var dismiss
    @State private var book: Book
    @State private var editing = false
    @State private var authorsText = ""
    @State private var categoriesText = ""
    @State private var showMetadata = false
    @State private var confirmDelete = false

    init(book: Book) { _book = State(initialValue: book) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        BookCover(url: book.thumbnail).frame(width: 110)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(book.title).font(.headline)
                            Text(book.authorText).font(.subheadline).foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                ReadBadge(read: book.isRead)
                                if book.isOnPicklist { Label("Pickliste", systemImage: "checklist").font(.caption2).foregroundStyle(.green) }
                            }
                            if let sh = store.shelf(book.bookshelfId) { ShelfDot(color: sh.color, name: sh.name) }
                        }
                    }
                }

                Section("Aktionen") {
                    Toggle("Gelesen", isOn: Binding(get: { book.isRead }, set: { nv in book.isRead = nv; Task { await store.toggleRead(bookWith(isRead: !nv)) } }))
                    Toggle("Auf Pickliste", isOn: Binding(get: { book.isOnPicklist }, set: { nv in book.isOnPicklist = nv; Task { await store.togglePicklist(bookWith(picklist: !nv)) } }))
                    Picker("Regal", selection: Binding(get: { book.bookshelfId ?? "" }, set: { nv in
                        book.bookshelfId = nv.isEmpty ? nil : nv; Task { await store.moveBook(book.id, to: book.bookshelfId) }
                    })) {
                        Text("Kein Regal").tag("")
                        ForEach(store.shelves) { s in Text(s.name).tag(s.id) }
                    }
                    Button { showMetadata = true } label: { Label("Metadaten aktualisieren", systemImage: "arrow.triangle.2.circlepath") }
                }

                if editing {
                    Section("Bearbeiten") {
                        TextField("Titel", text: $book.title)
                        TextField("Autor(en), kommagetrennt", text: $authorsText)
                        TextField("Verlag", text: Binding(get: { book.publisher ?? "" }, set: { book.publisher = $0 }))
                        TextField("Erscheinungsdatum", text: Binding(get: { book.publishedDate ?? "" }, set: { book.publishedDate = $0 }))
                        TextField("ISBN", text: Binding(get: { book.isbn ?? "" }, set: { book.isbn = $0 }))
                        TextField("Kategorien, kommagetrennt", text: $categoriesText)
                        TextField("Beschreibung", text: Binding(get: { book.description ?? "" }, set: { book.description = $0 }), axis: .vertical).lineLimit(2...6)
                    }
                } else {
                    Section("Details") {
                        detailRow("Verlag", book.publisher)
                        detailRow("Erscheinungsdatum", book.publishedDate)
                        if let pc = book.pageCount, pc > 0 { detailRow("Seiten", String(pc)) }
                        detailRow("ISBN", book.isbn)
                        detailRow("Sprache", book.language.map { BookFilters.languageLabel($0) })
                    }
                    if !book.categories.isEmpty {
                        Section("Kategorien") { CategoryPills(categories: book.categories) }
                    }
                    if let d = book.description, !d.isEmpty {
                        Section("Beschreibung") { Text(d).font(.callout) }
                    }
                }

                Section {
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Buch entfernen", systemImage: "trash") }
                }
            }
            .navigationTitle("Buch").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button(editing ? "Speichern" : "Bearbeiten") {
                        if editing { save() } else { startEdit() }
                    }
                }
            }
            .sheet(isPresented: $showMetadata) { MetadataUpdateSheet(book: book) { applied in book = applied } }
            .confirmationDialog("Buch löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { Task { await store.deleteBooks([book.id]); dismiss() } }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String?) -> some View {
        Group { if let v = value, !v.isEmpty { LabeledContent(label, value: v) } }
    }
    private func bookWith(isRead: Bool? = nil, picklist: Bool? = nil) -> Book {
        var b = book; if let isRead { b.isRead = isRead }; if let picklist { b.isOnPicklist = picklist }; return b
    }
    private func startEdit() {
        authorsText = book.authors.joined(separator: ", ")
        categoriesText = book.categories.joined(separator: ", ")
        editing = true
    }
    private func save() {
        book.authors = authorsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        book.categories = categoriesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        editing = false
        var f = book.apiFields(); f.removeValue(forKey: "is_read"); f.removeValue(forKey: "is_on_picklist")
        Task { await store.updateBookFields(book.id, f) }
    }
}
