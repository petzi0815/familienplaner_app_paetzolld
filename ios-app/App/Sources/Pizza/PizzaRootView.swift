import SwiftUI

/// Wurzel des Pizza-Bereichs — Segmente Planer und Rezepturen.
///
/// Haelt nur die Huelle: Kopf/Segmente/Menue und den Store. Der Planer rechnet im Store
/// (`PizzaStore.rechne`), die beiden Segment-Views holen sich alles per `@EnvironmentObject`.
struct PizzaRootView: View {
    @StateObject private var store: PizzaStore
    @State private var speichernAktiv = false
    @State private var rezeptName = ""
    @State private var shareItem: PizzaShareItem?

    init(settings: Settings) { _store = StateObject(wrappedValue: PizzaStore(settings: settings)) }

    private var tint: Color { Palette.colors(for: "pizza").first ?? Theme.accent }

    private var tabs: [(tab: PizzaTab, label: String, systemImage: String?)] {
        [(.planer, "Planer", "timer"), (.rezepte, "Rezepturen", "book.closed")]
    }

    var body: some View {
        AreaScaffold(gradientKey: "pizza", systemImage: "flame.fill", title: "Pizza machen",
                     subtitle: store.zusammenfassung,
                     toast: $store.message, toastIsError: store.messageIsError,
                     trailing: { menu },
                     controls: { SegmentBar(tabs: tabs, selection: $store.tab, gradientKey: "pizza") },
                     content: { content })
            .environmentObject(store)
            // Beim Betreten neu rechnen: `jetzt` ist beim letzten Lauf stehengeblieben, und die
            // 4,5-h-Vorlaufpruefung haengt daran (eine Stunde spaeter kann derselbe Plan zu knapp sein).
            .task { store.rechne(); await store.loadRezepte() }
            .alert("Als Rezeptur speichern", isPresented: $speichernAktiv) {
                TextField("Name", text: $rezeptName)
                Button("Abbrechen", role: .cancel) { }
                Button("Speichern") {
                    let name = rezeptName
                    rezeptName = ""
                    Task { await store.speichereAlsRezept(name: name) }
                }
            } message: {
                Text("Die aktuellen Einstellungen werden unter diesem Namen gespeichert – ohne die Essenszeit.")
            }
            .sheet(item: $shareItem) { ShareSheet(items: [$0.text]) }
    }

    /// Menue statt zwei Knoepfen: der Kopf soll auch bei langer Zusammenfassung schmal bleiben.
    private var menu: some View {
        Menu {
            // Eine Rezeptur ist reine Konfiguration — sie laesst sich auch dann speichern, wenn
            // die aktuelle Essenszeit (noch) keinen Plan zulaesst. Teilen braucht dagegen einen Plan.
            if store.tab == .planer {
                Button { speichernAktiv = true } label: {
                    Label("Als Rezeptur speichern", systemImage: "square.and.arrow.down")
                }
            }
            Button {
                if let p = store.aktiverPlan { shareItem = PizzaShareItem(text: PizzaShare.text(plan: p)) }
            } label: {
                Label("Teilen", systemImage: "square.and.arrow.up")
            }
            .disabled(store.aktiverPlan == nil)
        } label: {
            Image(systemName: "ellipsis.circle.fill").font(.title2).foregroundStyle(tint)
        }
        .accessibilityIdentifier("pizza-menu")
        .accessibilityLabel("Pizza-Aktionen")
    }

    @ViewBuilder private var content: some View {
        switch store.tab {
        case .planer: PizzaPlanerView()
        case .rezepte: PizzaRezepteView()
        }
    }
}
