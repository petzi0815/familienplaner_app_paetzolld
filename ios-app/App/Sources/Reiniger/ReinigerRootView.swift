import SwiftUI

/// Wurzel des nativen Reiniger-Bereichs — ersetzt den generischen Browser fuer `reiniger`.
/// Kopf (Verlaufs-Icon + Stats) + Segmente Inventar/Flecken/Einkauf + gemeinsames Suchfeld.
struct ReinigerRootView: View {
    @StateObject private var store: ReinigerStore

    init(settings: Settings) { _store = StateObject(wrappedValue: ReinigerStore(settings: settings)) }

    private var subtitle: String {
        guard store.stats.active > 0 || store.stats.useCases > 0 || !store.items.isEmpty else {
            return "Reinigungsmittel"
        }
        return "\(store.stats.active) Produkte · \(store.stats.useCases) Anwendungsfälle · \(store.stats.restock) nachkaufen"
    }

    private var tabs: [(tab: ReinigerTab, label: String, systemImage: String?)] {
        let inv = store.stats.active
        let flecken = store.anwendungen.count
        let einkauf = store.restockItems.count
        return [
            (.inventar, inv > 0 ? "Inventar (\(inv))" : "Inventar", "drop.fill"),
            (.ratgeber, flecken > 0 ? "Flecken (\(flecken))" : "Flecken", "target"),
            (.einkauf, einkauf > 0 ? "Einkauf (\(einkauf))" : "Einkauf", "cart"),
        ]
    }

    private var searchPlaceholder: String {
        store.tab == .ratgeber ? "Fleck, Material oder Pflege suchen …" : "Produkt, Marke, Oberfläche suchen …"
    }

    var body: some View {
        VStack(spacing: 0) {
            AreaHeader(gradientKey: "reiniger", systemImage: "sparkles", title: "Reiniger", subtitle: subtitle)
            SegmentBar(tabs: tabs, selection: $store.tab, gradientKey: "reiniger")
            AreaSearchField(placeholder: searchPlaceholder, text: $store.search)
            Divider()
            content
        }
        .background(Palette.gradient(for: "reiniger").opacity(0.05).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { if store.items.isEmpty && store.loading { await store.loadAll() } }
        .task(id: store.search) {
            guard store.initialized else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            if !Task.isCancelled { await store.reload() }
        }
        .environmentObject(store)
        .overlay(alignment: .bottom) { toast }
    }

    @ViewBuilder private var content: some View {
        if store.loading && store.items.isEmpty && store.anwendungen.isEmpty {
            ProgressView("Lädt …").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch store.tab {
            case .inventar: ReinigerInventarView()
            case .ratgeber: ReinigerGuideView()
            case .einkauf: ReinigerEinkaufView()
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
