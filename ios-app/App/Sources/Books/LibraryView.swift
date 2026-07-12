import SwiftUI

/// Bibliothek: Raster/Tabelle, Live-Suche, Filter/Sortierung, Mehrfachauswahl + Bulk-Aktionen.
struct LibraryView: View {
    @EnvironmentObject private var store: BooksStore
    @State private var grid = true
    @State private var showFilter = false
    @State private var detail: Book?
    @State private var showBulkMove = false
    @State private var showDuplicates = false
    @State private var showExport = false
    @State private var showSettings = false
    @State private var showAiCleaner = false
    @State private var showAiEnhancer = false
    private let gcols = [GridItem(.adaptive(minimum: 108), spacing: 10)]

    private var selectedBooks: [Book] { store.books.filter { store.selection.contains($0.id) } }
    private var enhancerBooks: [Book] { Array(store.books.filter { ($0.description ?? "").isEmpty || $0.categories.isEmpty }.prefix(20)) }

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            if store.selectionMode && !store.selection.isEmpty { bulkBar }
            searchBar
            content
        }
        .sheet(isPresented: $showFilter) { FilterSheet() }
        .sheet(item: $detail) { b in BookDetailView(book: b) }
        .sheet(isPresented: $showDuplicates) { DuplicateFinderSheet() }
        .sheet(isPresented: $showExport) { BooksExportSheet() }
        .sheet(isPresented: $showSettings) { BooksSettingsSheet() }
        .sheet(isPresented: $showAiCleaner) { AiCleanerSheet(books: selectedBooks) }
        .sheet(isPresented: $showAiEnhancer) { AiEnhancerSheet(books: enhancerBooks) }
        .confirmationDialog("Regal verschieben", isPresented: $showBulkMove, titleVisibility: .visible) {
            Button("Kein Regal") { Task { await store.bulkMove(to: nil) } }
            ForEach(store.shelves) { s in Button(s.name) { Task { await store.bulkMove(to: s.id) } } }
        }
    }

    // ── Aktionsleiste ──
    private var actionBar: some View {
        VStack(spacing: 8) {
            HStack {
                let total = store.books.count, shown = store.filteredBooks.count
                Text("\(shown) von \(total) Büchern").font(.subheadline.weight(.semibold))
                if store.filters.activeCount > 0 {
                    Text("\(store.filters.activeCount) Filter").font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(BookTheme.amber700.opacity(0.15), in: Capsule()).foregroundStyle(BookTheme.amber900)
                }
                Spacer()
                Menu {
                    Button { showDuplicates = true } label: { Label("Duplikate finden", systemImage: "doc.on.doc") }
                    Button { showAiEnhancer = true } label: { Label("KI: Metadaten ergänzen", systemImage: "sparkles") }
                    Button { showExport = true } label: { Label("Export / Backup", systemImage: "square.and.arrow.up") }
                    Button { showSettings = true } label: { Label("Einstellungen", systemImage: "gearshape") }
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                Button { store.selectionMode.toggle(); if !store.selectionMode { store.selection.removeAll() } } label: {
                    Label(store.selectionMode ? "Fertig" : "Auswählen", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                }
            }
            HStack(spacing: 10) {
                Button { showFilter = true } label: { Label("Filter", systemImage: "line.3.horizontal.decrease.circle") }
                    .font(.subheadline)
                Menu {
                    Picker("Sortieren", selection: $store.filters.sort) {
                        ForEach(SortField.allCases) { f in Text(f.label).tag(f) }
                    }
                    Toggle("Aufsteigend", isOn: $store.filters.sortAsc)
                } label: { Label("Sortieren", systemImage: "arrow.up.arrow.down") }.font(.subheadline)
                Spacer()
                Picker("", selection: $grid) {
                    Image(systemName: "square.grid.2x2").tag(true)
                    Image(systemName: "list.bullet").tag(false)
                }
                .pickerStyle(.segmented).frame(width: 96)
            }
        }
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 4)
    }

    private var bulkBar: some View {
        HStack(spacing: 10) {
            Text("\(store.selection.count) ausgewählt").font(.subheadline.weight(.semibold))
            Spacer()
            Button { showBulkMove = true } label: { Image(systemName: "folder") }
            Button { Task { await store.bulkSetRead(true) } } label: { Image(systemName: "book.closed") }
            Button { Task { await store.bulkSetRead(false) } } label: { Image(systemName: "book") }
            Button { showAiCleaner = true } label: { Image(systemName: "sparkles") }.foregroundStyle(.purple)
            Button(role: .destructive) { Task { await store.bulkDelete() } } label: { Image(systemName: "trash") }
            Button { store.selectAllFiltered() } label: { Image(systemName: "checkmark.circle.fill") }
        }
        .font(.title3)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(BookTheme.amber700.opacity(0.12))
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Bücher durchsuchen …", text: $store.filters.searchTerm)
            if !store.filters.searchTerm.isEmpty {
                Button { store.filters.searchTerm = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
        }
        .padding(10).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 14).padding(.vertical, 6)
    }

    @ViewBuilder private var content: some View {
        let list = store.filteredBooks
        if list.isEmpty {
            ContentUnavailableView("Keine Bücher gefunden", systemImage: "magnifyingglass",
                                   description: Text("Versuchen Sie es mit anderen Suchbegriffen oder Filtern."))
                .frame(maxHeight: .infinity)
        } else if grid {
            ScrollView {
                LazyVGrid(columns: gcols, spacing: 12) {
                    ForEach(list) { b in gridCell(b) }
                }
                .padding(12)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(list) { b in listRow(b); Divider() }
                }
            }
        }
    }

    private func gridCell(_ b: Book) -> some View {
        let selected = store.selection.contains(b.id)
        return VStack(alignment: .leading, spacing: 4) {
            BookCover(url: b.thumbnail, isbn: b.isbn)
                .overlay(alignment: .topTrailing) {
                    if store.selectionMode {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? .blue : .white).padding(4).background(.black.opacity(0.15), in: Circle()).padding(4)
                    }
                }
                .overlay(alignment: .bottomTrailing) { if b.isRead { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).padding(4) } }
                .onTapGesture { if store.selectionMode { store.toggleSelect(b.id) } else { detail = b } }
            Text(b.title).font(.caption2.weight(.semibold)).lineLimit(2)
            Text(b.authorText).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            if let sh = store.shelf(b.bookshelfId) { ShelfDot(color: sh.color, name: sh.name) }
        }
        .overlay(selected ? RoundedRectangle(cornerRadius: 10).stroke(.blue, lineWidth: 2) : nil)
        .contentShape(Rectangle())
        .onTapGesture { if store.selectionMode { store.toggleSelect(b.id) } }
    }

    private func listRow(_ b: Book) -> some View {
        let selected = store.selection.contains(b.id)
        return HStack(spacing: 12) {
            if store.selectionMode {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? .blue : .secondary)
            }
            BookCover(url: b.thumbnail, isbn: b.isbn).frame(width: 40, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(b.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(b.authorText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let sh = store.shelf(b.bookshelfId) { ShelfDot(color: sh.color, name: sh.name) }
            }
            Spacer()
            ReadBadge(read: b.isRead)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { if store.selectionMode { store.toggleSelect(b.id) } else { detail = b } }
    }
}
