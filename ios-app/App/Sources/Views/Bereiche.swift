import SwiftUI

/// Statischer Katalog: Domain-Schlüssel → Titel + Emoji + Reihenfolge (Farben kommen aus Palette).
enum DomainCatalog {
    static let meta: [String: (title: String, emoji: String)] = [
        "termine": ("Termine", "📅"),
        "abfuhrkalender": ("Abfuhr", "🗑️"),
        "reisen": ("Reisen", "✈️"),
        "samu": ("Samu", "🧸"),
        "geschenkplaner": ("Geschenke", "🎁"),
        "wunschliste": ("Wunschliste", "⭐️"),
        "garten": ("Garten", "🌱"),
        "vorratskammer": ("Vorrat", "🥫"),
        "gypsi": ("Gypsi", "🐾"),
        "reiniger": ("Reiniger", "🧽"),
        "elisbooks": ("Bücher", "📚"),
        "ebooks": ("E-Books", "📖"),
        "smarthome": ("Smart Home", "🏠"),
        "vertraege": ("Verträge", "📄"),
    ]
    static let order = ["termine", "abfuhrkalender", "reisen", "samu", "geschenkplaner", "garten", "vorratskammer",
                        "wunschliste", "gypsi", "reiniger", "elisbooks", "ebooks", "smarthome", "vertraege"]

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
struct BereicheHubView: View {
    @EnvironmentObject private var app: AppState
    @State private var showSettings = false
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if app.domains.isEmpty {
                    ProgressView("Lädt Bereiche …").padding(.top, 80)
                } else {
                    LazyVGrid(columns: cols, spacing: 14) {
                        ForEach(app.domains) { d in
                            NavigationLink { BereichView(domain: d) } label: { BereichTile(domain: d) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("bereich-tile-\(d.key)")
                        }
                    }
                    .padding()
                }
            }
            .background(Palette.gradient(for: "termine").opacity(0.06).ignoresSafeArea())
            .navigationTitle("Bereiche")
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
}

struct BereichTile: View {
    let domain: BereichDomain
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(domain.emoji).font(.system(size: 34))
            Spacer(minLength: 0)
            Text(domain.title).font(.headline).foregroundStyle(.white).lineLimit(1)
            Text("\(domain.resources.count) \(domain.resources.count == 1 ? "Liste" : "Listen")")
                .font(.caption).foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .padding(16)
        .background(Palette.gradient(for: domain.key), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Palette.colors(for: domain.key).first!.opacity(0.35), radius: 10, y: 5)
    }
}

/// Bereich → Ressourcen. Reisen bleibt trip-zentriert; 1 Ressource → direkt in die Liste; mehrere → Auswahl.
struct BereichView: View {
    @EnvironmentObject private var app: AppState
    let domain: BereichDomain

    var body: some View {
        Group {
            if domain.key == "reisen" {
                ReiseListView()
            } else if domain.key == "elisbooks" {
                BooksRootView(settings: app.settings)
            } else if domain.key == "abfuhrkalender" {
                AbfuhrCalendarView()
            } else if domain.key == "samu" {
                SamuRootView(settings: app.settings)
            } else if domain.key == "garten" {
                GartenRootView(settings: app.settings)
            } else if domain.key == "geschenkplaner" {
                GeschenkRootView(settings: app.settings)
            } else if domain.key == "termine" {
                TermineRootView(settings: app.settings)
            } else if domain.key == "vorratskammer" {
                VorratRootView(settings: app.settings)
            } else if domain.key == "wunschliste" {
                WunschlisteRootView(settings: app.settings)
            } else if domain.key == "gypsi" {
                GypsiRootView(settings: app.settings)
            } else if domain.key == "reiniger" {
                ReinigerRootView(settings: app.settings)
            } else if domain.key == "ebooks" {
                EbooksRootView(settings: app.settings)
            } else if domain.key == "smarthome" {
                SmartHomeRootView(settings: app.settings)
            } else if domain.key == "vertraege" {
                VertraegeRootView(settings: app.settings)
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
}
