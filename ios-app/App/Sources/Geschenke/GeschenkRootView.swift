import SwiftUI

/// Wurzel des nativen Geschenkplaner-Bereichs — ersetzt den generischen Browser fuer `geschenkplaner`.
/// Kopf + Segmente (Übersicht/Einkauf/Kinder/Archiv) + aktive Ansicht. Detailansichten (Ereignis, Kind)
/// werden als NavigationLink im umgebenden NavigationStack gepusht.
struct GeschenkRootView: View {
    @StateObject private var store: GeschenkStore

    init(settings: Settings) { _store = StateObject(wrappedValue: GeschenkStore(settings: settings)) }

    private var tabs: [(tab: GeschenkTab, label: String, systemImage: String?)] {
        [
            (.uebersicht, "Übersicht", "chart.bar"),
            (.einkauf, "Einkauf", "cart"),
            (.kinder, "Kinder", "person.2"),
            (.archiv, "Archiv", "shippingbox"),
        ]
    }

    var body: some View {
        AreaScaffold(gradientKey: "geschenkplaner", systemImage: "gift.fill",
                     title: "Geschenkplaner", subtitle: "Geschenke für jeden Anlass",
                     toast: $store.message, toastIsError: store.messageIsError,
                     controls: { SegmentBar(tabs: tabs, selection: $store.tab, gradientKey: "geschenkplaner") },
                     content: { content })
            .environmentObject(store)
    }

    @ViewBuilder private var content: some View {
        switch store.tab {
        case .uebersicht: GeschenkDashboardView()
        case .einkauf: GeschenkEinkaufView()
        case .kinder: GeschenkKinderView()
        case .archiv: GeschenkArchivView()
        }
    }
}
