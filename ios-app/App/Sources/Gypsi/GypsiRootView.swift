import SwiftUI

/// Wurzel des nativen Gypsi-Bereichs — ersetzt den generischen Browser für `gypsi`.
/// Kopf + Statuspills/Filter/Liste + Verlaufs-FAB zum Hinzufügen. KEIN eigener
/// NavigationStack (wird in Bereiche.swift bereits in einen gepusht).
struct GypsiRootView: View {
    @StateObject private var store: GypsiStore
    @State private var showAdd = false

    init(settings: Settings) { _store = StateObject(wrappedValue: GypsiStore(settings: settings)) }

    var body: some View {
        AreaScaffold(gradientKey: "gypsi", systemImage: "pawprint.fill",
                     title: "Gypsis Futter", subtitle: "Futter-Vorlieben & Tracking",
                     toast: $store.message, toastIsError: store.messageIsError,
                     content: { content })
            .task { if store.all.isEmpty && store.loading { await store.loadAll() } }
            .environmentObject(store)
            .overlay(alignment: .bottomTrailing) { fab }
            .sheet(isPresented: $showAdd) { GypsiAddSheet().environmentObject(store) }
    }

    @ViewBuilder private var content: some View {
        if store.loading && store.all.isEmpty {
            ProgressView("Lade Futter …").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GypsiListView()
        }
    }

    private var fab: some View {
        Button { showAdd = true } label: {
            Label("Futter hinzufügen", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18).padding(.vertical, 14)
                .background(Palette.gradient(for: "gypsi"), in: Capsule())
                .foregroundStyle(.white)
                .shadow(color: Palette.colors(for: "gypsi").first!.opacity(0.4), radius: 10, y: 5)
        }
        .padding(.trailing, 18).padding(.bottom, 20)
    }
}
