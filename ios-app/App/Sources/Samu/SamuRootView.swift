import SwiftUI

/// Wurzel des nativen Samu-Bereichs — ersetzt den generischen Browser für `samu`.
/// Kopf (Verlaufs-Icon + Teile/Wert) + Segmente Inventar/Übersicht/Bedarf + aktive Ansicht.
struct SamuRootView: View {
    @StateObject private var store: SamuStore

    init(settings: Settings) { _store = StateObject(wrappedValue: SamuStore(settings: settings)) }

    private var subtitle: String {
        guard store.stats.gesamt > 0 || !store.items.isEmpty else { return "Samus Sachen" }
        let wert = store.stats.geschaetzterWert
        return "\(store.stats.gesamt) Teile · ~\(Int(wert.rounded()))€"
    }

    private var tabs: [(tab: SamuTab, label: String, systemImage: String?)] {
        let offen = store.offeneBedarf.count
        return [
            (.inventar, "Inventar", "shippingbox"),
            (.uebersicht, "Übersicht", "square.grid.3x3"),
            (.bedarf, offen > 0 ? "Bedarf (\(offen))" : "Bedarf", "cart"),
        ]
    }

    var body: some View {
        AreaScaffold(gradientKey: "samu", systemImage: "teddybear.fill", title: "Samu", subtitle: subtitle,
                     toast: $store.message, toastIsError: store.messageIsError,
                     controls: { SegmentBar(tabs: tabs, selection: $store.tab, gradientKey: "samu") },
                     content: { content })
            .task { if store.items.isEmpty && store.loading { await store.loadAll() } }
            .environmentObject(store)
    }

    @ViewBuilder private var content: some View {
        if store.loading && store.items.isEmpty {
            ProgressView("Lädt …").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch store.tab {
            case .inventar: SamuInventarView()
            case .uebersicht: SamuMatrixView()
            case .bedarf: SamuBedarfView()
            }
        }
    }
}
