import SwiftUI

/// „Bibliothek"-Tab: die echte Calibre-Web-Bibliothek — durchsuchbar, nach Regal filterbar,
/// mit Covern; ein Buch antippen → auf ein Regal legen. Nur lesen + Regal (kein Löschen/Ändern).
struct CalibreView: View {
    @EnvironmentObject private var store: EbooksStore
    @State private var shelfPickerBook: CalibreBook?
    private let cols = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            AreaSearchField(placeholder: "Bibliothek durchsuchen …", text: $store.calibreSearch)
            shelfFilter
            content
        }
        .onChange(of: store.calibreSearch) { _, _ in store.calibreSearchChanged() }
        .task { if store.calibreBooks.isEmpty && store.calibreShelves.isEmpty { await store.loadCalibre() } }
        .sheet(item: $shelfPickerBook) { book in shelfPicker(book) }
    }

    // ── Regal-Filter ──
    private var shelfFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterPill(label: "Alle", selected: store.calibreShelf == nil, color: Theme.accent) {
                    Task { await store.setCalibreShelf(nil) }
                }
                ForEach(store.calibreShelves) { s in
                    FilterPill(label: s.name, selected: store.calibreShelf == s.id, color: EbookStyle.indigo) {
                        Task { await store.setCalibreShelf(s.id) }
                    }
                    .accessibilityIdentifier("calibre-shelf-\(s.id)")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }

    @ViewBuilder private var content: some View {
        if store.calibreLoading && store.calibreBooks.isEmpty {
            ProgressView("Lädt Bibliothek …").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.calibreBooks.isEmpty {
            AreaEmptyState(emoji: "📚", title: "Keine Bücher", hint: "Andere Suche oder anderes Regal wählen.")
                .frame(minHeight: 240)
        } else {
            ScrollView {
                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(store.calibreBooks) { b in bookCell(b) }
                }
                .padding(14)
                if store.calibreShelf == nil && store.calibreBooks.count < store.calibreTotal {
                    Button { Task { await store.calibreLoadMore() } } label: {
                        if store.calibreLoadingMore { ProgressView() }
                        else { Text("Mehr laden (\(String(store.calibreBooks.count))/\(String(store.calibreTotal)))").font(.footnote.weight(.semibold)) }
                    }
                    .buttonStyle(.bordered).padding(.bottom, 24)
                }
            }
            .refreshable { await store.calibreReload() }
        }
    }

    private func bookCell(_ b: CalibreBook) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            cover(b)
            Text(b.title).font(.caption.weight(.semibold)).lineLimit(2)
            if !b.authors.isEmpty {
                Text(b.authors).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { shelfPickerBook = b }
        .accessibilityIdentifier("calibre-book-\(b.id)")
    }

    private func cover(_ b: CalibreBook) -> some View {
        Group {
            if let p = b.coverPath {
                AuthImage(path: p, contentMode: .fill)
            } else {
                Palette.gradient(for: "ebooks").opacity(0.85).overlay(Text("📚").font(.largeTitle).opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // ── Auf Regal legen ──
    private func shelfPicker(_ book: CalibreBook) -> some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.calibreShelves) { s in
                        Button { Task { await store.addToShelf(book, shelf: s); shelfPickerBook = nil } } label: {
                            Label(s.name, systemImage: "text.badge.plus")
                        }
                    }
                } header: {
                    Text(book.title)
                }
            }
            .navigationTitle("Auf Regal legen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { shelfPickerBook = nil } } }
        }
        .presentationDetents([.medium, .large])
    }
}
