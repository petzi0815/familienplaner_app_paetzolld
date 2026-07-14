import SwiftUI

/// Ratgeber-Tab ("Flecken"): 2-Stufen-Berater. Oberflaeche waehlen -> passende Faelle,
/// darunter eine Produkt-Info-Fallbackliste (Flecken/Pflege/Sicherheit je Produkt).
struct ReinigerGuideView: View {
    @EnvironmentObject private var store: ReinigerStore
    @State private var surface = "alle"
    @State private var detail: ReinigerProdukt?

    private var visible: [ReinigerAnwendung] {
        guard surface != "alle" else { return store.anwendungen }
        return store.anwendungen.filter { $0.surface == surface }
    }

    var body: some View {
        ScrollView {
            if store.items.isEmpty && store.anwendungen.isEmpty {
                AreaEmptyState(emoji: "🎯", title: "Noch keine Flecken- oder Pflegehinweise erfasst")
                    .frame(minHeight: 260)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    surfaceStep
                    caseStep
                    if !store.produktInfos.isEmpty { produktInfoStep }
                }
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 24)
            }
        }
        .refreshable { await store.loadAll() }
        .sheet(item: $detail) { p in
            ReinigerDetailSheet(productID: p.id).environmentObject(store)
        }
    }

    // MARK: - Schritt 1: Oberflaeche

    private var surfaceStep: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("1. Oberfläche").font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.surfaces, id: \.self) { s in
                        FilterPill(label: s == "alle" ? "Alle" : s, selected: surface == s, color: Color(hex: "1C1C1E")) {
                            withAnimation(.snappy(duration: 0.2)) { surface = s }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Schritt 2: Fleck / Anwendungsfall

    private var caseStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("2. Fleck oder Anwendungsfall").font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
            if visible.isEmpty {
                AreaEmptyState(emoji: "🔎", title: "Für diese Oberfläche ist noch kein Fall erfasst")
                    .frame(minHeight: 180)
            } else {
                ForEach(visible) { a in
                    ReinigerUseCaseCard(anwendung: a,
                                        matched: store.product(id: a.reinigerID),
                                        onOpenProduct: { detail = $0 })
                }
            }
        }
    }

    // MARK: - Produkt-Info-Fallback

    private var produktInfoStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Produkt-Info").font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
            ForEach(store.produktInfos) { p in
                ReinigerProduktInfoCard(produkt: p) { detail = p }
            }
        }
    }
}

// MARK: - Anwendungsfall-Karte

struct ReinigerUseCaseCard: View {
    let anwendung: ReinigerAnwendung
    var matched: ReinigerProdukt?
    var onOpenProduct: (ReinigerProdukt) -> Void

    private var imagePath: String? { anwendung.produktImagePath ?? matched?.imagePath }
    private var produktLabel: String {
        if anwendung.produktLabel != "Produkt" { return anwendung.produktLabel }
        return matched?.name ?? "Produkt"
    }
    private var externalURL: URL? { anwendung.externalURL ?? matched?.externalURL }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let path = imagePath {
                AuthImage(path: path, contentMode: .fill)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(anwendung.title).font(.subheadline.weight(.semibold))
                if let s = anwendung.surface, !s.isEmpty {
                    Text("Auf: \(s)").font(.caption).foregroundStyle(.secondary)
                }
                produktLink
                if let b = anwendung.begruendung, !b.isEmpty {
                    Text("Warum: \(b)").font(.caption).foregroundStyle(.secondary)
                }
                if let anleitung = anwendung.anleitung, !anleitung.isEmpty {
                    Text(anleitung).font(.caption).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                }
                if let w = anwendung.warnhinweise, !w.isEmpty {
                    Text("Achtung: \(w)").font(.caption).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder private var produktLink: some View {
        if let url = externalURL {
            Link(destination: url) {
                Label("Produkt: \(produktLabel)", systemImage: "link").font(.caption.weight(.medium))
            }
        } else if let m = matched {
            Button { onOpenProduct(m) } label: {
                Label("Produkt: \(produktLabel)", systemImage: "chevron.right.circle").font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
        } else {
            Text("Produkt: \(produktLabel)").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Produkt-Info-Karte (Fallback)

struct ReinigerProduktInfoCard: View {
    let produkt: ReinigerProdukt
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(produkt.name).font(.subheadline.weight(.semibold))
            if let f = produkt.flecken, !f.isEmpty {
                Text("Flecken: \(f)").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let p = produkt.pflegehinweise, !p.isEmpty {
                Text("Pflege: \(p)").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let s = produkt.sicherheit, !s.isEmpty {
                Text("Sicherheit: \(s)").font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }
}
