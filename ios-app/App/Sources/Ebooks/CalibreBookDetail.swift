import SwiftUI

/// Detailseite eines Calibre-Buchs: Cover + Metadaten + Beschreibung, und Regale zuordnen/entfernen
/// (Häkchen = liegt auf dem Regal → tippen entfernt; leer → tippen legt darauf).
struct CalibreBookDetail: View {
    let book: CalibreBook
    @EnvironmentObject private var store: EbooksStore
    @Environment(\.dismiss) private var dismiss
    @State private var full: CalibreBook
    @State private var shelfIds: Set<Int> = []
    @State private var loading = true
    @State private var busyShelf: Int?

    init(book: CalibreBook) { self.book = book; _full = State(initialValue: book) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    meta
                    if let d = full.description, !d.isEmpty { NoteBlock(icon: "📖", text: d, tint: EbookStyle.rose) }
                    shelvesSection
                }
                .padding()
            }
            .navigationTitle("Buch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if let p = full.coverPath { AuthImage(path: p, contentMode: .fit) }
                else { Palette.gradient(for: "ebooks").opacity(0.85).overlay(Text("📚").font(.largeTitle)) }
            }
            .frame(width: 96, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(full.title).font(.title3.weight(.bold))
                if !full.authors.isEmpty { Text(full.authors).foregroundStyle(EbookStyle.rose) }
                if let s = full.series, !s.isEmpty { Pill(text: "📚 \(s)", color: EbookStyle.purple, filled: false) }
            }
            Spacer(minLength: 0)
        }
    }

    private var meta: some View {
        VStack(spacing: 0) {
            if let v = full.publisher, !v.isEmpty { InfoRow(icon: "🏢", label: "Verlag", value: v) }
            if let v = full.published, !v.isEmpty { InfoRow(icon: "📅", label: "Jahr", value: v) }
            if let v = full.languages, !v.isEmpty { InfoRow(icon: "🌐", label: "Sprache", value: v) }
            if let v = full.rating, !v.isEmpty { InfoRow(icon: "⭐️", label: "Bewertung", value: v) }
            if let v = full.isbn, !v.isEmpty { InfoRow(icon: "🔖", label: "ISBN", value: v) }
            if !full.tags.isEmpty { InfoRow(icon: "🏷️", label: "Tags", value: full.tags.joined(separator: ", ")) }
        }
    }

    private var shelvesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Regale", systemImage: "books.vertical").font(.headline)
                if loading { ProgressView().padding(.leading, 4) }
            }
            if store.calibreShelves.isEmpty {
                Text("Keine Regale geladen.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(store.calibreShelves) { s in shelfRow(s) }
            }
        }
    }

    private func shelfRow(_ s: CalibreShelf) -> some View {
        let on = shelfIds.contains(s.id)
        return Button { Task { await toggle(s) } } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? EbookStyle.green : .secondary)
                Text(s.name)
                Spacer()
                if busyShelf == s.id { ProgressView() }
                else { Image(systemName: on ? "minus.circle" : "plus.circle").foregroundStyle(on ? .red : Theme.accent) }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(busyShelf != nil)
        .accessibilityIdentifier("calibre-detail-shelf-\(s.id)")
    }

    private func load() async {
        loading = true
        if let d = try? await store.api.calibreBookDetail(id: book.id, title: book.title) {
            shelfIds = Set(d.shelfIds)
            if let f = d.book { full = f }
        }
        loading = false
    }

    private func toggle(_ s: CalibreShelf) async {
        let isOn = shelfIds.contains(s.id)
        busyShelf = s.id
        defer { busyShelf = nil }
        do {
            _ = try await store.api.calibreShelfAction(bookId: book.id, shelfId: s.id, action: isOn ? "remove" : "add")
            if isOn { shelfIds.remove(s.id) } else { shelfIds.insert(s.id) }
            store.notify(isOn ? "Von „\(s.name)“ entfernt" : "Auf „\(s.name)“ gelegt")
        } catch {
            store.notify((error as? APIError)?.errorDescription ?? "Fehler", error: true)
        }
    }
}
