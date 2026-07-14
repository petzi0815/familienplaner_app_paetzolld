import SwiftUI

/// Wurzel des nativen Smart-Home-Bereichs — ersetzt den generischen Browser fuer `smarthome`.
/// Kopf (Verlaufs-Icon + Entity/Raum-Zusammenfassung) + Segmente Geraete/Beziehungen/Command-Log
/// + aktive Ansicht. Wird im umgebenden NavigationStack gepusht (KEIN eigener Stack am Root).
struct SmartHomeRootView: View {
    @StateObject private var store: SmartHomeStore

    init(settings: Settings) { _store = StateObject(wrappedValue: SmartHomeStore(settings: settings)) }

    private var subtitle: String {
        guard store.loaded else { return "Home Assistant" }
        return "\(store.stats.totalEntities) Entities · \(store.stats.totalAreas) Räume"
    }

    private var tabs: [(tab: SmartHomeTab, label: String, systemImage: String?)] {
        [
            (.geraete, "Geräte", "house"),
            (.beziehungen, "Beziehungen", "point.3.connected.trianglepath.dotted"),
            (.log, "Command Log", "list.bullet.rectangle"),
        ]
    }

    var body: some View {
        AreaScaffold(gradientKey: "smarthome", systemImage: "house.fill", title: "Smart Home", subtitle: subtitle,
                     toast: $store.message, toastIsError: store.messageIsError,
                     controls: { SegmentBar(tabs: tabs, selection: $store.tab, gradientKey: "smarthome") },
                     content: { content })
            .task { if !store.loaded { await store.loadAll() } }
            .environmentObject(store)
    }

    @ViewBuilder private var content: some View {
        if store.loading && !store.loaded {
            ProgressView("Lädt …").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch store.tab {
            case .geraete: SmartHomeEntitiesView()
            case .beziehungen: SmartHomeRelationsView()
            case .log: SmartHomeLogView()
            }
        }
    }
}
