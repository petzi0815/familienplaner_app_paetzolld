import SwiftUI
import UIKit

/// Zentraler Zustand des Verträge-Bereichs: Rohzeilen laden, clientseitig gruppieren/rechnen,
/// Filter/Sortierung für die Listenansicht, Mutationen (agent-gated → 403 wird als Toast gezeigt).
@MainActor
final class VertraegeStore: ObservableObject {
    let api: VertraegeAPI

    @Published var vertraege: [Vertrag] = []
    @Published var loading = true
    @Published var message: String?
    @Published var messageIsError = false

    @Published var tab: VertraegeTab = .uebersicht
    @Published var filters = VertraegeFilters()
    @Published var expanded: Set<String> = []

    init(settings: Settings) { api = VertraegeAPI(settings: settings) }

    // MARK: - Laden

    func loadAll() async {
        loading = true
        if let list = try? await api.fetchAll() { vertraege = list }
        loading = false
    }

    // MARK: - Abgeleitet: Kategorie-Gruppen

    /// Gruppen in Akkordeon-Reihenfolge: bekannte Katalog-Kategorien zuerst (feste Ordnung),
    /// unbekannte danach in Erst-Auftreten-Reihenfolge.
    var gruppen: [VertragGruppe] {
        var byName: [String: [Vertrag]] = [:]
        var seen: [String] = []
        for v in vertraege {
            let name = v.kategorieName
            if byName[name] == nil { seen.append(name) }
            byName[name, default: []].append(v)
        }
        let built: [String: VertragGruppe] = seen.reduce(into: [:]) { acc, name in
            let items = byName[name] ?? []
            let icon = VertragStyle.icon(for: name, meta: items.first?.metaIcon)
            let color = VertragStyle.color(for: name, metaHex: items.first?.metaColorHex)
            let monat = items.reduce(0.0) { $0 + $1.monatlich }
            acc[name] = VertragGruppe(name: name, icon: icon, color: color, contracts: items, monatlich: monat)
        }
        let known = VertragStyle.catOrder.filter { byName[$0] != nil }
        let unknown = seen.filter { !VertragStyle.catOrder.contains($0) }
        return (known + unknown).compactMap { built[$0] }
    }

    /// Gruppen absteigend nach Monatskosten (Summenbalken, Legende, Top-Posten).
    var gruppenNachKosten: [VertragGruppe] { gruppen.sorted { $0.monatlich > $1.monatlich } }

    var totalMonatlich: Double { gruppen.reduce(0) { $0 + $1.monatlich } }
    var totalJaehrlich: Double { totalMonatlich * 12 }

    /// Jüngstes `aktualisiert_am` als „Stand"-Datum der Übersicht.
    var standText: String? {
        guard let latest = vertraege.compactMap({ $0.aktualisiertAm }).max() else { return nil }
        return DateText.pretty(latest)
    }

    // MARK: - Abgeleitet: Listenansicht (gefiltert + sortiert)

    var listVisible: [Vertrag] {
        var arr = vertraege
        if let k = filters.kategorie { arr = arr.filter { $0.kategorieName == k } }
        let q = filters.search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            arr = arr.filter { v in
                [v.anbieter, v.bezeichnung, v.kategorie, v.vertragsnummer, v.kundennummer, v.notizen]
                    .compactMap { $0?.lowercased() }
                    .contains { $0.contains(q) }
            }
        }
        switch filters.sort {
        case .kategorie: arr.sort { ($0.kategorieName, $0.anbieter ?? "") < ($1.kategorieName, $1.anbieter ?? "") }
        case .anbieter: arr.sort { ($0.anbieter ?? "") < ($1.anbieter ?? "") }
        case .kostenDesc: arr.sort { $0.monatlich > $1.monatlich }
        }
        return arr
    }

    /// Vorhandene Kategorien in Katalog-Reihenfolge (für die Filter-Pills).
    var availableKategorien: [String] {
        let present = Set(vertraege.map { $0.kategorieName })
        let known = VertragStyle.catOrder.filter { present.contains($0) }
        let unknown = present.subtracting(known).sorted()
        return known + unknown
    }

    // MARK: - Mutationen (agent-gated)

    /// Anlegen (id == nil) oder aktualisieren.
    func save(id: Int?, fields: [String: Any]) async -> Bool {
        do {
            if let id { _ = try await api.update(id, fields) }
            else { _ = try await api.create(fields) }
            await loadAll()
            notify(id == nil ? "Vertrag angelegt" : "Gespeichert")
            return true
        } catch {
            notify(errText(error), error: true)
            return false
        }
    }

    func delete(_ v: Vertrag) async {
        do {
            try await api.delete(v.id)
            await loadAll()
            notify("Gelöscht")
        } catch {
            notify(errText(error), error: true)
        }
    }

    /// Vertragsnummer in die Zwischenablage (native CopyButton-Entsprechung).
    func copy(_ text: String) {
        UIPasteboard.general.string = text
        notify("Kopiert!")
    }

    // MARK: - Helfer

    func notify(_ text: String, error: Bool = false) { message = text; messageIsError = error }
    private func errText(_ e: Error) -> String { (e as? APIError)?.errorDescription ?? "Fehler" }
}
