import SwiftUI

/// Wurzel des nativen Verträge-Bereichs — ersetzt den generischen Browser für `vertraege`.
/// Kopf (Verlaufs-Icon + Anzahl/Monatskosten + „+") + Segmente Übersicht/Verträge + aktive Ansicht.
struct VertraegeRootView: View {
    @StateObject private var store: VertraegeStore
    @State private var editing: VertragEditRef?

    init(settings: Settings) { _store = StateObject(wrappedValue: VertraegeStore(settings: settings)) }

    private var subtitle: String {
        guard !store.vertraege.isEmpty else { return "Familien-Verträge" }
        let n = store.vertraege.count
        return "\(n) \(n == 1 ? "Vertrag" : "Verträge") · ~\(VertragFmt.eur(store.totalMonatlich))/Mo"
    }

    private var tabs: [(tab: VertraegeTab, label: String, systemImage: String?)] {
        [(.uebersicht, "Übersicht", "chart.pie.fill"),
         (.liste, "Verträge", "list.bullet")]
    }

    var body: some View {
        AreaScaffold(gradientKey: "vertraege", systemImage: "doc.text.fill", title: "Verträge", subtitle: subtitle,
                     toast: $store.message, toastIsError: store.messageIsError, toastSeconds: 2.0,
                     trailing: {
                         Button { editing = VertragEditRef(vertrag: nil) } label: {
                             Image(systemName: "plus.circle.fill").font(.title2)
                         }
                         .foregroundStyle(Theme.accent)
                         .accessibilityLabel("Neuer Vertrag")
                     },
                     controls: { SegmentBar(tabs: tabs, selection: $store.tab, gradientKey: "vertraege") },
                     content: { content })
            .task { if store.vertraege.isEmpty && store.loading { await store.loadAll() } }
            .environmentObject(store)
            .sheet(item: $editing) { ref in
                VertragEditSheet(existing: ref.vertrag).environmentObject(store)
            }
    }

    @ViewBuilder private var content: some View {
        if store.loading && store.vertraege.isEmpty {
            ProgressView("Lädt …").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.vertraege.isEmpty {
            AreaEmptyState(emoji: "📄", title: "Noch keine Verträge",
                           hint: "Lege den ersten Vertrag über + oben rechts an.")
        } else {
            switch store.tab {
            case .uebersicht: VertraegeOverviewView()
            case .liste: VertraegeListView()
            }
        }
    }
}
