import SwiftUI
import UIKit

/// Zentraler Zustand des Wein-Bereichs (Weine, Bewertungen, Preis-Historie, Tab/Suche/Filter).
/// Die Liste wird EINMAL geladen und danach clientseitig gefiltert und sortiert — der Keller ist
/// klein genug, und so bleiben Tab-Wechsel und Tippen in der Suche ohne Netz-Rundreise.
@MainActor
final class WeinStore: ObservableObject, NotifiableStore {
    let api: WeinAPI

    @Published var message: String?
    @Published var messageIsError = false

    @Published var weine: [Wein] = []
    /// Bewertungen je Wein-ID (maximal zwei: Lars und Elita).
    @Published var bewertungen: [Int: [WeinBewertung]] = [:]
    /// Preis-Historie je Wein-ID — wird nur bei Bedarf (Detailseite) nachgeladen.
    @Published var preise: [Int: [WeinPreis]] = [:]

    @Published var tab: WeinTab = .alle
    @Published var suche = ""
    @Published var loading = true

    @Published var filterTyp: Set<WeinTyp> = []
    @Published var filterRebsorte: String?
    @Published var filterLand: String?
    @Published var filterMinSterne: Int?
    @Published var sort: WeinSort = .neueste

    /// Angemeldete Person (lars | elita) — setzt das RootView aus `AppState.me`.
    /// Ohne Person gilt jeder Wein als "von mir noch nicht bewertet".
    var owner: String?

    init(settings: Settings) { api = WeinAPI(settings: settings) }

    // MARK: - Laden

    func loadAll() async {
        loading = true
        await fetch()
        loading = false
    }

    /// Neu laden ohne Ladeanzeige (Pull-to-Refresh, nach Mutationen).
    func reload() async { await fetch() }

    /// Weine + Bewertungen parallel holen. Fehlgeschlagene Teilabfragen lassen den bisherigen
    /// Stand stehen (statt die Liste leer zu raeumen).
    private func fetch() async {
        async let weineT = api.fetchWeine()
        async let bewertungenT = api.fetchBewertungen()
        let neueWeine = try? await weineT
        let neueBewertungen = try? await bewertungenT
        if let neueWeine { weine = neueWeine }
        if let neueBewertungen { bewertungen = Dictionary(grouping: neueBewertungen, by: { $0.weinId }) }
    }

    /// Preis-Historie eines Weins nachladen (Detailseite).
    func loadPreise(_ wein: Wein) async {
        if let list = try? await api.fetchPreise(weinId: wein.id) { preise[wein.id] = list }
    }

    // MARK: - Bewertungen

    /// Bewertung der angemeldeten Person (nil = noch nicht bewertet).
    func meine(_ wein: Wein) -> WeinBewertung? {
        guard let owner, !owner.isEmpty else { return nil }
        return (bewertungen[wein.id] ?? []).first { $0.owner == owner }
    }

    /// Bewertung der jeweils anderen Person.
    func andere(_ wein: Wein) -> WeinBewertung? {
        let list = bewertungen[wein.id] ?? []
        guard let owner, !owner.isEmpty else { return list.first }
        return list.first { $0.owner != owner }
    }

    /// Durchschnitt beider Bewertungen (nil = noch keine).
    func schnitt(_ wein: Wein) -> Double? {
        let sterne = (bewertungen[wein.id] ?? []).map { $0.sterne }.filter { $0 > 0 }
        guard !sterne.isEmpty else { return nil }
        return Double(sterne.reduce(0, +)) / Double(sterne.count)
    }

    // MARK: - Abgeleitete Listen

    var alleRebsorten: [String] {
        Array(Set(weine.flatMap { $0.rebsorten })).filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var alleLaender: [String] {
        Array(Set(weine.compactMap { $0.land })).filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Reihenfolge: Tab → Suchtext → Typ/Rebsorte/Land/Mindeststerne → Sortierung.
    var gefiltert: [Wein] {
        var out = weine

        switch tab {
        case .alle:   break
        case .keller: out = out.filter { $0.bestand > 0 }
        case .top:    out = out.filter { (schnitt($0) ?? 0) >= 4 }
        case .offen:  out = out.filter { meine($0) == nil }
        }

        let q = suche.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            out = out.filter { w in
                w.name.lowercased().contains(q)
                    || w.weingut.lowercased().contains(q)
                    || (w.region ?? "").lowercased().contains(q)
                    || w.rebsorten.contains { $0.lowercased().contains(q) }
                    || w.aromen.contains { $0.lowercased().contains(q) }
            }
        }

        if !filterTyp.isEmpty { out = out.filter { filterTyp.contains($0.typ) } }
        if let r = filterRebsorte, !r.isEmpty { out = out.filter { $0.rebsorten.contains(r) } }
        if let l = filterLand, !l.isEmpty { out = out.filter { $0.land == l } }
        if let s = filterMinSterne { out = out.filter { (schnitt($0) ?? 0) >= Double(s) } }

        return sortiert(out)
    }

    /// Sortierung. Unbekannte Werte (kein Schnitt/Jahrgang/Preis) landen immer hinten.
    private func sortiert(_ list: [Wein]) -> [Wein] {
        switch sort {
        case .neueste:
            return list.sorted { $0.id > $1.id }
        case .bewertung:
            return list.sorted { a, b in
                let sa = schnitt(a), sb = schnitt(b)
                if let sa, let sb { return sa == sb ? a.id > b.id : sa > sb }
                if sa != nil { return true }
                if sb != nil { return false }
                return a.id > b.id
            }
        case .name:
            return list.sorted { a, b in
                let r = a.titel.localizedCaseInsensitiveCompare(b.titel)
                return r == .orderedSame ? a.id > b.id : r == .orderedAscending
            }
        case .jahrgang:
            return list.sorted { a, b in
                switch (a.jahrgang, b.jahrgang) {
                case let (ja?, jb?): return ja == jb ? a.id > b.id : ja > jb
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.id > b.id
                }
            }
        case .preis:
            return list.sorted { a, b in
                let pa = a.besterPreis ?? a.referenzpreis
                let pb = b.besterPreis ?? b.referenzpreis
                switch (pa, pb) {
                case let (x?, y?): return x == y ? a.id > b.id : x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.id > b.id
                }
            }
        }
    }

    /// Filter/Suche zuruecksetzen (Knopf im Filter-Sheet).
    func filterZuruecksetzen() {
        filterTyp = []
        filterRebsorte = nil
        filterLand = nil
        filterMinSterne = nil
        suche = ""
    }

    var filterAktiv: Bool {
        !filterTyp.isEmpty || filterRebsorte != nil || filterLand != nil || filterMinSterne != nil
    }

    // MARK: - Mutationen

    /// Anlegen (id == nil) oder aendern. Gibt die ID des gespeicherten Weins zurueck, nil bei Fehler.
    @discardableResult
    func save(_ fields: [String: Any], id: Int?) async -> Int? {
        do {
            let w: Wein
            if let id { w = try await api.update(id, fields) } else { w = try await api.create(fields) }
            ersetzeOderErgaenze(w)
            notify(id == nil ? "Wein gespeichert" : "Änderungen gespeichert")
            return w.id > 0 ? w.id : id
        } catch {
            notify(errText(error), error: true)
            return nil
        }
    }

    /// Gibt zurueck, ob der Server die Bewertung wirklich angenommen hat. Aufrufer duerfen den Erfolg
    /// NICHT aus dem Store-Zustand ableiten: eine unveraendert wieder gespeicherte Bewertung sieht
    /// dort genauso aus wie eine abgelehnte.
    @discardableResult
    func bewerten(_ wein: Wein, sterne: Int, kommentar: String) async -> Bool {
        do {
            let r = try await api.bewerten(weinId: wein.id, sterne: sterne, kommentar: kommentar, owner: owner)
            var list = bewertungen[wein.id] ?? []
            if let i = list.firstIndex(where: { $0.owner == r.bewertung.owner }) { list[i] = r.bewertung }
            else { list.append(r.bewertung) }
            bewertungen[wein.id] = list
            notify("Bewertung gespeichert")
            return true
        } catch {
            notify(errText(error), error: true)
            return false
        }
    }

    /// Flaschenzahl im Keller setzen (optimistisch, bei Fehler zurueckgedreht).
    func setBestand(_ wein: Wein, _ n: Int) async {
        let neu = max(0, n)
        let alt = wein.bestand
        guard neu != alt else { return }
        patchLokal(wein.id) { $0.bestand = neu }
        do {
            let w = try await api.update(wein.id, ["bestand": neu])
            ersetzeOderErgaenze(w)
        } catch {
            patchLokal(wein.id) { $0.bestand = alt }
            notify(errText(error), error: true)
        }
    }

    /// Preis-Waechter fuer diesen Wein an-/abschalten.
    func setBeobachten(_ wein: Wein, _ an: Bool) async {
        let alt = wein.preisBeobachten
        guard an != alt else { return }
        patchLokal(wein.id) { $0.preisBeobachten = an }
        do {
            let w = try await api.update(wein.id, ["preis_beobachten": an ? 1 : 0])
            ersetzeOderErgaenze(w)
            notify(an ? "Preis wird beobachtet" : "Preisbeobachtung aus")
        } catch {
            patchLokal(wein.id) { $0.preisBeobachten = alt }
            notify(errText(error), error: true)
        }
    }

    func delete(_ wein: Wein) async {
        do {
            try await api.delete(wein.id)
            weine.removeAll { $0.id == wein.id }
            bewertungen[wein.id] = nil
            preise[wein.id] = nil
            notify("Gelöscht")
        } catch {
            notify(errText(error), error: true)
        }
    }

    /// Preise dieses Weins jetzt pruefen lassen; danach Wein + Historie nachziehen.
    func preischeck(_ wein: Wein) async {
        do {
            let e = try await api.preischeck(weinId: wein.id)
            if let frisch = try? await api.fetchWein(wein.id) { ersetzeOderErgaenze(frisch) }
            await loadPreise(wein)
            if let best = e.bester, let p = WeinFormat.preis(best.preis) {
                let haendler = best.haendler.isEmpty ? "" : " bei \(best.haendler)"
                notify("Bester Preis: \(p)\(haendler)")
            } else if let grund = e.fehler {
                // Klartext des Backends (fehlender API-Key, Suche nicht erreichbar, …) statt einer
                // Pauschalmeldung — sonst sucht man den Fehler beim Wein statt in der Konfiguration.
                notify(grund, error: true)
            } else {
                notify("Kein Angebot gefunden")
            }
        } catch {
            notify(errText(error), error: true)
        }
    }

    /// Etikettenfoto hochladen → storage_key fuer `foto_key`. nil bei Fehler (Speichern laeuft
    /// dann ohne Bild weiter).
    func uploadFoto(_ image: UIImage) async -> String? {
        guard let jpeg = image.jpegForUpload() else { return nil }
        return try? await api.uploadFoto(jpeg: jpeg)
    }

    // MARK: - Lokaler Cache

    private func patchLokal(_ id: Int, _ mutate: (inout Wein) -> Void) {
        if let i = weine.firstIndex(where: { $0.id == id }) { mutate(&weine[i]) }
    }

    private func ersetzeOderErgaenze(_ w: Wein) {
        guard w.id > 0 else { return }
        if let i = weine.firstIndex(where: { $0.id == w.id }) { weine[i] = w } else { weine.insert(w, at: 0) }
    }

    // notify(_:error:) und errText(_:) kommen aus NotifiableStore.
}
