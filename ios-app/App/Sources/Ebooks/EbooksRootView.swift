import SwiftUI

/// Wurzel des nativen E-Book-Bereichs — ersetzt den generischen Browser für `ebooks`.
/// Kopf + Segmente (Wunschliste / Buch suchen) + aktive Ansicht. Wird innerhalb des
/// bestehenden NavigationStack gepusht → hier KEIN eigener NavigationStack.
struct EbooksRootView: View {
    @StateObject private var store: EbooksStore

    init(settings: Settings) { _store = StateObject(wrappedValue: EbooksStore(settings: settings)) }

    private var subtitle: String {
        guard !store.items.isEmpty else { return "Wunschliste · Suche · Downloads" }
        return "\(store.statGesamt) Bücher · \(store.statGeladen) geladen"
    }

    private var tabs: [(tab: EbookTab, label: String, systemImage: String?)] {
        [
            (.wunschliste, "Wunschliste", "list.star"),
            (.bibliothek, "Bibliothek", "books.vertical.fill"),
            (.suche, "Buch suchen", "magnifyingglass"),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            AreaHeader(gradientKey: "ebooks", systemImage: "books.vertical.fill", title: "E-Books", subtitle: subtitle)
            SegmentBar(tabs: tabs, selection: $store.tab, gradientKey: "ebooks")
            Divider()
            content
        }
        .background(Palette.gradient(for: "ebooks").opacity(0.05).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { if store.items.isEmpty && store.loading { await store.loadAll() } }
        .environmentObject(store)
        .overlay(alignment: .bottom) { toast }
    }

    @ViewBuilder private var content: some View {
        if store.loading && store.items.isEmpty {
            ProgressView("Lädt …").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch store.tab {
            case .wunschliste: EbooksWishlistView()
            case .bibliothek: CalibreView()
            case .suche: EbooksSearchView()
            }
        }
    }

    @ViewBuilder private var toast: some View {
        if let m = store.message {
            AreaToast(message: m, isError: store.messageIsError)
                .task { try? await Task.sleep(nanoseconds: 2_500_000_000); store.message = nil }
        }
    }
}
