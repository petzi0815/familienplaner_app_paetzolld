import SwiftUI

/// Wurzel des nativen Garten-Bereichs — ersetzt den generischen Browser für `garten`.
/// Kopf (Verlaufs-Icon + Stats + GTS-Badge) + Segmente + aktive Ansicht + GTS-Detail-Sheet.
struct GartenRootView: View {
    @StateObject private var store: GartenStore

    init(settings: Settings) { _store = StateObject(wrappedValue: GartenStore(settings: settings)) }

    private var subtitle: String {
        guard let s = store.stats else { return "Unser Garten" }
        return "\(s.pflanzenAktiv) Pflanzen · \(s.samenAktiv) Samen · \(s.aufgabenOffen) offen"
    }

    private var tabs: [(tab: GartenTab, label: String, systemImage: String?)] {
        [
            (.pflanzen, "Pflanzen", "leaf"),
            (.samen, "Samen", "camera.macro"),
            (.pflege, "Pflege", "checklist"),
            (.pflanz, "Pflanz", "calendar"),
            (.duenger, "Dünger", "drop.fill"),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            AreaHeader(gradientKey: "garten", systemImage: "leaf.fill", title: "Garten", subtitle: subtitle) {
                headerTrailing
            }
            SegmentBar(tabs: tabs, selection: $store.tab, gradientKey: "garten")
            Divider()
            content
        }
        .background(Palette.gradient(for: "garten").opacity(0.05).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { if store.loading { await store.load() } }
        .environmentObject(store)
        .overlay(alignment: .bottom) { toast }
        .sheet(isPresented: $store.showGTS) {
            if let g = store.gts { GartenGTSSheet(gts: g) }
        }
    }

    @ViewBuilder private var content: some View {
        if store.loading {
            ProgressView("Lädt …").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch store.tab {
            case .pflanzen: GartenPflanzenView()
            case .samen: GartenSamenView()
            case .pflege: GartenPflegeView()
            case .pflanz: GartenPflanzplanView()
            case .duenger: GartenDuengerView()
            }
        }
    }

    @ViewBuilder private var headerTrailing: some View {
        if let g = store.gts, g.hasData { gtsBadge(g) }
    }

    // GTS-Kompaktbadge im Header-Trailing → öffnet das Detail-Sheet.
    private func gtsBadge(_ g: GTSResult) -> some View {
        let pct = min(1.0, max(0, g.current / 200))
        let barW = CGFloat(pct) * 34
        return Button { store.showGTS = true } label: {
            HStack(spacing: 5) {
                Text("🌡️").font(.caption2)
                Text("\(Int(g.current.rounded()))").font(.caption.weight(.bold))
                Text("/200").font(.caption2).foregroundStyle(.secondary)
                Capsule().fill(Color(.tertiarySystemFill)).frame(width: 34, height: 5)
                    .overlay(alignment: .leading) {
                        Capsule().fill(GartenStyle.gtsColor(g.current)).frame(width: barW, height: 5)
                    }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color(.secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var toast: some View {
        if let m = store.message {
            AreaToast(message: m, isError: store.messageIsError)
                .task { try? await Task.sleep(nanoseconds: 3_500_000_000); store.message = nil }
        }
    }
}
