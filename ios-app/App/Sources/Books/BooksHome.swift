import SwiftUI

/// Wurzel der nativen ElisBooks-App — ersetzt den generischen Browser für den Bücher-Bereich.
/// Kopf (Logo + aktives Regal + Regale-Button) + Segment-Navigation + aktive View.
struct BooksRootView: View {
    @StateObject private var store: BooksStore

    init(settings: Settings) { _store = StateObject(wrappedValue: BooksStore(settings: settings)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            navBar
            Divider()
            content
        }
        .background(BookTheme.bgWash.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { if store.books.isEmpty && store.shelves.isEmpty { await store.loadAll() } }
        .environmentObject(store)
        .overlay(alignment: .bottom) { toast }
    }

    // ── Kopf ──
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "books.vertical.fill").font(.title3).foregroundStyle(BookTheme.amber700)
            Text("ElisBooks").font(.title3.weight(.heavy)).foregroundStyle(BookTheme.amber900)
            Spacer()
            if !store.shelves.isEmpty {
                Menu {
                    Button { store.activeShelf = nil } label: { Text("Kein aktives Regal") }
                    ForEach(store.shelves) { s in
                        Button { store.activeShelf = s.id } label: {
                            if store.activeShelf == s.id { Label(s.name, systemImage: "checkmark") } else { Text(s.name) }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle().fill(BookTheme.shelfColor(store.shelf(store.activeShelf)?.color)).frame(width: 9, height: 9)
                        Text(store.shelf(store.activeShelf)?.name ?? "Aktives Regal").font(.subheadline.weight(.medium)).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .foregroundStyle(BookTheme.amber900)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
            Button { store.currentView = .shelves } label: {
                Image(systemName: "square.grid.2x2.fill").foregroundStyle(BookTheme.amber700)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // ── Navigation (Segmente) ──
    private var navBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                navChip(.books, "Bücher", "list.bullet")
                navChip(.wishlist, "Wunschliste", "heart")
                navChip(.scanner, "Scanner", "barcode.viewfinder")
                navChip(.bulkScanner, "Bulk", "square.stack.3d.up")
                navChip(.shelfScanner, "Regalscan", "camera.viewfinder")
                navChip(.ocrScanner, "OCR", "doc.viewfinder")
                navChip(.manual, "Manuell", "plus.circle")
                navChip(.similar, "Vorschläge", "sparkles")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }
    private func navChip(_ v: BooksView, _ label: String, _ icon: String) -> some View {
        let sel = store.currentView == v
        return Button { store.currentView = v } label: {
            Label(label, systemImage: icon).font(.footnote.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(sel ? AnyShapeStyle(BookTheme.brandGradient) : AnyShapeStyle(Color(.secondarySystemBackground)), in: Capsule())
                .foregroundStyle(sel ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // ── Inhalt ──
    @ViewBuilder private var content: some View {
        if store.loading && store.books.isEmpty {
            ProgressView("Bibliothek laden …").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch store.currentView {
            case .shelves: ShelvesView()
            case .books: LibraryView()
            case .wishlist: WishlistView()
            case .scanner: BookScannerView(mode: .single)
            case .bulkScanner: BookScannerView(mode: .bulk)
            case .manual: ManualBookSearchView()
            case .similar: SuggestionsView()
            case .shelfScanner: ShelfScanView()
            case .ocrScanner: ShelfScanView()
            }
        }
    }

    @ViewBuilder private var toast: some View {
        if let m = store.message {
            Label(m, systemImage: store.messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.subheadline.weight(.medium)).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(store.messageIsError ? Color.red : Color.green, in: Capsule())
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task { try? await Task.sleep(nanoseconds: 2_500_000_000); store.message = nil }
        }
    }
}
