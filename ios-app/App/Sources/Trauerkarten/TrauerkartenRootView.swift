import SwiftUI

/// Wurzel des nativen Trauerkarten-Bereichs — Segmente „Trauerkarten" / „Kostenübersicht".
/// Respektvoll-ruhige Slate-Optik der Original-App (Lovable memories-app).
struct TrauerkartenRootView: View {
    @StateObject private var store: TrauerkartenStore
    @State private var addKarte = false
    @State private var addKosten = false
    @State private var showPersonen = false

    init(settings: Settings) { _store = StateObject(wrappedValue: TrauerkartenStore(settings: settings)) }

    private var subtitle: String {
        if store.karten.isEmpty && store.kosten.isEmpty { return "Erinnerung & Kostenübersicht" }
        return "\(store.kartenAnzahl) Karten · \(TrauerStyle.eur(store.trauerkartenSumme))"
    }
    private var tabs: [(tab: TrauerTab, label: String, systemImage: String?)] {
        [(.karten, "Trauerkarten", "square.grid.2x2"), (.kosten, "Kostenübersicht", "eurosign.circle")]
    }

    var body: some View {
        AreaScaffold(gradientKey: "trauerkarten", systemImage: "leaf.fill", title: "Trauerkarten", subtitle: subtitle,
                     toast: $store.message, toastIsError: store.messageIsError,
                     trailing: { toolbarButton },
                     controls: {
                         SegmentBar(tabs: tabs, selection: $store.tab, gradientKey: "trauerkarten")
                         if store.tab == .karten { AreaSearchField(placeholder: "Karten suchen …", text: $store.search) }
                     },
                     content: { content })
            .task { if store.karten.isEmpty && store.loading { await store.loadAll() } }
            .environmentObject(store)
            .sheet(isPresented: $addKarte) { TrauerkarteFormSheet(karte: nil).environmentObject(store) }
            .sheet(isPresented: $addKosten) { KostenFormSheet(eintrag: nil).environmentObject(store) }
            .sheet(isPresented: $showPersonen) { PersonenVerwaltungSheet().environmentObject(store) }
    }

    @ViewBuilder private var toolbarButton: some View {
        switch store.tab {
        case .karten:
            Button { addKarte = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                .foregroundStyle(TrauerStyle.primary)
                .accessibilityLabel("Neue Trauerkarte")
        case .kosten:
            Menu {
                Button { addKosten = true } label: { Label("Neuer Eintrag", systemImage: "plus") }
                Button { showPersonen = true } label: { Label("Personen verwalten", systemImage: "person.2") }
            } label: {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(TrauerStyle.primary)
            }
            .accessibilityIdentifier("kosten-menu")
        }
    }

    @ViewBuilder private var content: some View {
        if store.loading && store.karten.isEmpty && store.kosten.isEmpty {
            ProgressView("Lädt …").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch store.tab {
            case .karten: TrauerkartenListView()
            case .kosten: KostenUebersichtView()
            }
        }
    }
}
