import SwiftUI

/// Wurzel des nativen Vorratskammer-Bereichs — ersetzt den generischen Browser für `vorratskammer`.
/// Kopf (Verlaufs-Icon + Kennzahlen) + Segmente Vorrat/Einkauf/Ablaufend/Rezepte + aktive Ansicht.
/// Wird innerhalb eines bestehenden NavigationStack gepusht — hier KEIN eigener Stack.
struct VorratRootView: View {
    @StateObject private var store: VorratStore

    init(settings: Settings) { _store = StateObject(wrappedValue: VorratStore(settings: settings)) }

    private var subtitle: String {
        let s = store.stats
        if s.total == 0 && store.einkauf.isEmpty && store.ablaufend.isEmpty { return "Lebensmittel & MHD" }
        return "\(s.total) Produkte · \(s.einkaufsliste) Einkauf · \(s.ablaufend) ablaufend"
    }

    private var tabs: [(tab: VorratTab, label: String, systemImage: String?)] {
        let s = store.stats
        return [
            (.vorrat,    s.total > 0 ? "Vorrat (\(s.total))" : "Vorrat", "shippingbox"),
            (.einkauf,   s.einkaufsliste > 0 ? "Einkauf (\(s.einkaufsliste))" : "Einkauf", "cart"),
            (.ablaufend, s.ablaufend > 0 ? "Ablaufend (\(s.ablaufend))" : "Ablaufend", "clock.badge.exclamationmark"),
            (.rezepte,   store.rezepte.isEmpty ? "Rezepte" : "Rezepte (\(store.rezepte.count))", "fork.knife"),
        ]
    }

    var body: some View {
        AreaScaffold(gradientKey: "vorratskammer", systemImage: "fork.knife", title: "Vorratskammer", subtitle: subtitle,
                     toast: $store.message, toastIsError: store.messageIsError,
                     controls: { SegmentBar(tabs: tabs, selection: $store.tab, gradientKey: "vorratskammer") },
                     content: { content })
            .task { if store.loading && store.items.isEmpty { await store.loadAll() } }
            .environmentObject(store)
    }

    @ViewBuilder private var content: some View {
        if store.loading && store.items.isEmpty && store.einkauf.isEmpty && store.ablaufend.isEmpty && store.rezepte.isEmpty {
            ProgressView("Lädt …").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch store.tab {
            case .vorrat:    VorratVorratView()
            case .einkauf:   VorratEinkaufView()
            case .ablaufend: VorratAblaufendView()
            case .rezepte:   VorratRezepteView()
            }
        }
    }
}
