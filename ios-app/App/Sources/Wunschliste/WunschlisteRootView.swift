import SwiftUI

/// Wurzel des nativen Wunschliste-Bereichs — ersetzt den generischen Browser für `wunschliste`.
/// Kopf (Verlaufs-Icon + „+"-Menü) → Event-Chipleiste → aktive Ansicht (gruppiert / flach).
struct WunschlisteRootView: View {
    @StateObject private var store: WunschlisteStore

    @State private var showAddItem = false
    @State private var showAddEvent = false

    init(settings: Settings) { _store = StateObject(wrappedValue: WunschlisteStore(settings: settings)) }

    private var subtitle: String {
        let s = store.stats
        if store.items.isEmpty { return "Samus Geschenkideen" }
        if let ev = store.selectedEvent { return "\(ev.name) · \(s.total) Ideen · \(s.offen) offen" }
        return "\(s.total) Ideen · \(s.offen) offen · \(store.events.count) Anlässe"
    }

    var body: some View {
        AreaScaffold(gradientKey: "wunschliste", systemImage: "gift.fill",
                     title: "Samus Wunschliste", subtitle: subtitle,
                     toast: $store.message, toastIsError: store.messageIsError,
                     trailing: { addMenu },
                     controls: { WunschEventChipBar(store: store) },
                     content: { content })
            .task { if store.events.isEmpty && store.loading { await store.loadAll() } }
            .environmentObject(store)
            .sheet(isPresented: $showAddItem) {
                WunschItemFormSheet(defaultEventID: store.selectedEventID).environmentObject(store)
            }
            .sheet(isPresented: $showAddEvent) {
                WunschEventFormSheet().environmentObject(store)
            }
    }

    // ── „+"-Menü (Event immer, Geschenk wenn Anlässe existieren) + deaktivierte 501-Aktion ──
    private var addMenu: some View {
        Menu {
            Button { showAddItem = true } label: { Label("Geschenk hinzufügen", systemImage: "gift") }
                .disabled(store.events.isEmpty)
            Button { showAddEvent = true } label: { Label("Neuer Anlass", systemImage: "calendar.badge.plus") }
            if store.enrichableCount > 0 {
                Divider()
                // Externe Bild-Anreicherung ist im Backend nicht migriert (501) → deaktiviert.
                Button {} label: { Label("Bilder anreichern (nicht verfügbar)", systemImage: "wand.and.stars") }
                    .disabled(true)
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(WunschStyle.accent)
        }
        .accessibilityIdentifier("wunsch-add-menu")
    }

    @ViewBuilder private var content: some View {
        if store.loading && store.items.isEmpty && store.events.isEmpty {
            VStack(spacing: 10) {
                Text("🎁").font(.system(size: 44))
                Text("Lade Wunschliste …").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            WunschItemsView(onAddItem: { showAddItem = true })
                .environmentObject(store)
        }
    }
}
