import SwiftUI

/// Zentrale Registry aller Lebensbereiche — EINE Quelle für Titel/Emoji/Reihenfolge UND die Root-View.
/// Einen neuen Bereich hinzufügen = EIN Eintrag hier (statt vorher: DomainCatalog.meta + .order + BereichView-Switch).
struct BereichDef {
    let key: String
    let title: String
    let emoji: String
    /// Native Root-View des Bereichs (nil → generischer Ressourcen-Browser). @MainActor, da UI-Views erzeugt werden.
    let makeRoot: (@MainActor (Settings) -> AnyView)?
}

let BEREICH_REGISTRY: [BereichDef] = [
    .init(key: "termine",         title: "Termine",     emoji: "📅",  makeRoot: { AnyView(TermineRootView(settings: $0)) }),
    .init(key: "abfuhrkalender",  title: "Abfuhr",      emoji: "🗑️",  makeRoot: { _ in AnyView(AbfuhrCalendarView()) }),
    .init(key: "reisen",          title: "Reisen",      emoji: "✈️",  makeRoot: { _ in AnyView(ReiseListView()) }),
    .init(key: "samu",            title: "Samu",        emoji: "🧸",  makeRoot: { AnyView(SamuRootView(settings: $0)) }),
    .init(key: "geschenkplaner",  title: "Geschenke",   emoji: "🎁",  makeRoot: { AnyView(GeschenkRootView(settings: $0)) }),
    .init(key: "garten",          title: "Garten",      emoji: "🌱",  makeRoot: { AnyView(GartenRootView(settings: $0)) }),
    .init(key: "vorratskammer",   title: "Vorrat",      emoji: "🥫",  makeRoot: { AnyView(VorratRootView(settings: $0)) }),
    .init(key: "wunschliste",     title: "Wunschliste", emoji: "⭐️",  makeRoot: { AnyView(WunschlisteRootView(settings: $0)) }),
    .init(key: "gypsi",           title: "Gypsi",       emoji: "🐾",  makeRoot: { AnyView(GypsiRootView(settings: $0)) }),
    .init(key: "reiniger",        title: "Reiniger",    emoji: "🧽",  makeRoot: { AnyView(ReinigerRootView(settings: $0)) }),
    .init(key: "elisbooks",       title: "Bücher",      emoji: "📚",  makeRoot: { AnyView(BooksRootView(settings: $0)) }),
    .init(key: "ebooks",          title: "E-Books",     emoji: "📖",  makeRoot: { AnyView(EbooksRootView(settings: $0)) }),
    .init(key: "smarthome",       title: "Smart Home",  emoji: "🏠",  makeRoot: { AnyView(SmartHomeRootView(settings: $0)) }),
    .init(key: "vertraege",       title: "Verträge",    emoji: "📄",  makeRoot: { AnyView(VertraegeRootView(settings: $0)) }),
]

private let BEREICH_BY_KEY: [String: BereichDef] = Dictionary(uniqueKeysWithValues: BEREICH_REGISTRY.map { ($0.key, $0) })

/// Statischer Katalog (Titel/Emoji/Reihenfolge) — aus BEREICH_REGISTRY abgeleitet (Single Source).
enum DomainCatalog {
    static let order: [String] = BEREICH_REGISTRY.map(\.key)
    static let meta: [String: (title: String, emoji: String)] =
        Dictionary(uniqueKeysWithValues: BEREICH_REGISTRY.map { ($0.key, (title: $0.title, emoji: $0.emoji)) })

    static func build(from resources: [ResourceInfo]) -> [BereichDomain] {
        var byDomain: [String: [ResourceInfo]] = [:]
        for r in resources where r.domain != "system" && r.domain != "foto" {
            byDomain[r.domain, default: []].append(r)
        }
        let ordered = order.filter { byDomain[$0] != nil } + byDomain.keys.filter { !order.contains($0) }.sorted()
        return ordered.map { d in
            let m = meta[d] ?? (d.prefix(1).uppercased() + d.dropFirst(), "📦")
            return BereichDomain(key: d, title: m.title, emoji: m.emoji, resources: byDomain[d] ?? [])
        }
    }

    /// Statische Bereichsliste (alle bekannten Domains, ohne Ressourcen) — für den UI-Test-Modus
    /// ohne Backend. Routing ist key-basiert, daher genügen key/title/emoji.
    static func buildStatic() -> [BereichDomain] {
        order.map { d in
            let m = meta[d] ?? (d.prefix(1).uppercased() + d.dropFirst(), "📦")
            return BereichDomain(key: d, title: m.title, emoji: m.emoji, resources: [])
        }
    }
}

/// „Bereiche"-Tab: farbiges Kachel-Grid aller Lebensbereiche. Einstellungen per Zahnrad.
/// Der Navigationspfad hängt an AppState → Home-KPI-Kacheln können direkt in einen Bereich springen.
struct BereicheHubView: View {
    @EnvironmentObject private var app: AppState
    @State private var showSettings = false
    // Kompaktes Raster: mehr Bereiche pro Bildschirm (≈3 Spalten auf dem iPhone) ohne Scrollen.
    private let cols = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        NavigationStack(path: $app.bereichePath) {
            ScrollView {
                if app.domains.isEmpty {
                    ProgressView("Lädt Bereiche …").padding(.top, 80)
                } else {
                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(app.domains) { d in
                            NavigationLink(value: d.key) { BereichTile(domain: d) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("bereich-tile-\(d.key)")
                        }
                    }
                    .padding()
                }
            }
            .background(Palette.gradient(for: "termine").opacity(0.06).ignoresSafeArea())
            .navigationTitle("Bereiche")
            .navigationDestination(for: String.self) { key in
                BereichView(domain: domainForKey(key))
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Einstellungen")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsSheet() }
            .task { await app.loadCapabilities() }
            .refreshable { app.domains = []; await app.loadCapabilities() }
        }
    }

    /// Domain zum Key: aus den geladenen Domains, sonst minimal aus dem Katalog (Deep-Link vor dem
    /// Capabilities-Laden; native Bereiche routen key-basiert und brauchen keine Ressourcenliste).
    private func domainForKey(_ key: String) -> BereichDomain {
        if let d = app.domains.first(where: { $0.key == key }) { return d }
        let m = DomainCatalog.meta[key] ?? (key.prefix(1).uppercased() + key.dropFirst(), "📦")
        return BereichDomain(key: key, title: m.title, emoji: m.emoji, resources: [])
    }
}

struct BereichTile: View {
    let domain: BereichDomain
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(domain.emoji).font(.system(size: 30))
            Spacer(minLength: 0)
            Text(domain.title)
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding(12)
        .background(Palette.gradient(for: domain.key), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Palette.colors(for: domain.key).first!.opacity(0.3), radius: 7, y: 4)
    }
}

/// Bereich → native Root-View aus der Registry; unbekannte/generische Domains → Ressourcen-Browser.
struct BereichView: View {
    @EnvironmentObject private var app: AppState
    let domain: BereichDomain

    var body: some View {
        if let make = BEREICH_BY_KEY[domain.key]?.makeRoot {
            make(app.settings)
        } else if domain.resources.count == 1 {
            ResourceListView(resource: domain.resources[0])
        } else {
            List(domain.resources) { r in
                NavigationLink { ResourceListView(resource: r) } label: {
                    Label(r.label, systemImage: r.image != nil ? "photo.stack" : "list.bullet")
                }
            }
            .navigationTitle(domain.title)
        }
    }
}
