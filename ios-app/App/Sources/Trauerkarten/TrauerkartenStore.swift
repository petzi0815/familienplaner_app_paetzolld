import SwiftUI

/// Zentraler Zustand des Trauerkarten-Bereichs (Karten, Personen, Kosten) + abgeleitete Summen,
/// Kostenverteilung und Ausgleichszahlungen (Formeln 1:1 aus der Original-App).
@MainActor
final class TrauerkartenStore: ObservableObject, NotifiableStore {
    let api: TrauerkartenAPI

    @Published var karten: [Trauerkarte] = []
    @Published var personen: [TrauerPerson] = []
    @Published var kosten: [KostenEintrag] = []

    @Published var tab: TrauerTab = .karten
    @Published var search = ""
    @Published var loading = true
    @Published var message: String?
    @Published var messageIsError = false

    init(settings: Settings) { api = TrauerkartenAPI(settings: settings) }

    // MARK: - Laden
    func loadAll() async {
        loading = true
        async let k = api.fetchKarten()
        async let p = api.fetchPersonen()
        async let ko = api.fetchKosten()
        karten = (try? await k) ?? []
        personen = (try? await p) ?? []
        kosten = (try? await ko) ?? []
        loading = false
    }
    func reloadKarten() async { if let k = try? await api.fetchKarten() { karten = k } }
    func reloadKosten() async { if let k = try? await api.fetchKosten() { kosten = k } }
    func reloadPersonen() async { if let p = try? await api.fetchPersonen() { personen = p } }

    // MARK: - Lookups
    func person(_ id: Int?) -> TrauerPerson? { id.flatMap { pid in personen.first { $0.id == pid } } }
    func personName(_ id: Int?) -> String { person(id)?.name ?? "Alle Personen" }

    // MARK: - Karten: Suche + Summe
    var visibleKarten: [Trauerkarte] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return karten }
        return karten.filter { $0.name.lowercased().contains(q) || $0.trauertext.lowercased().contains(q) }
    }
    var trauerkartenSumme: Double { karten.reduce(0) { $0 + $1.geldbetrag } }
    var kartenAnzahl: Int { karten.count }

    // MARK: - Kostenübersicht-Summen (Screen-Ebene)
    var summeEinnahmen: Double { kosten.filter { $0.istEinnahme }.reduce(0) { $0 + $1.betrag } + trauerkartenSumme }
    var summeAusgaben: Double { kosten.filter { !$0.istEinnahme }.reduce(0) { $0 + $1.betrag } }
    var saldo: Double { summeEinnahmen - summeAusgaben }
    /// Anzahl Einträge (manuelle + 1 Sammelzeile für die Trauerkarten) — wie im Original.
    var eintraegeAnzahl: Int { kosten.count + 1 }

    /// Trauerkarten-Spenden nach Person gruppiert (Kostenliste, „Einnahme automatisch").
    var spendenNachPerson: [(person: TrauerPerson?, karten: [Trauerkarte], summe: Double)] {
        var order: [Int] = []; var buckets: [Int: [Trauerkarte]] = [:]
        let noKey = -1
        for k in karten {
            let key = k.personId ?? noKey
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(k)
        }
        return order.map { key in
            let list = buckets[key] ?? []
            return (person(key == noKey ? nil : key), list, list.reduce(0) { $0 + $1.geldbetrag })
        }
    }

    // MARK: - Kostenverteilung pro Person (informativ; nicht-zugeordnetes gleichmäßig auf alle)
    var verteilung: [PersonSaldo] {
        let n = personen.count
        guard n > 0 else { return [] }
        var einn: [Int: Double] = [:]; var ausg: [Int: Double] = [:]
        for p in personen { einn[p.id] = 0; ausg[p.id] = 0 }
        for k in karten {
            if let pid = k.personId, einn[pid] != nil { einn[pid]! += k.geldbetrag }
            else { for p in personen { einn[p.id]! += k.geldbetrag / Double(n) } }
        }
        for e in kosten {
            if let pid = e.personId, einn[pid] != nil {
                if e.istEinnahme { einn[pid]! += e.betrag } else { ausg[pid]! += e.betrag }
            } else {
                let anteil = e.betrag / Double(n)
                for p in personen { if e.istEinnahme { einn[p.id]! += anteil } else { ausg[p.id]! += anteil } }
            }
        }
        return personen.map { PersonSaldo(id: $0.id, name: $0.name, einnahmen: einn[$0.id] ?? 0, ausgaben: ausg[$0.id] ?? 0) }
    }

    // MARK: - Ausgleichszahlungen (Verrechnung nach fairem Anteil an den Netto-Gesamtkosten)
    /// Saldo je Person: >0 → hat mehr als fair getragen (Gläubiger), <0 → zahlt (Schuldner).
    private var ausgleichSalden: [(name: String, value: Double)] {
        let n = personen.count
        guard n > 0 else { return [] }
        var gEinn = 0.0, gAusg = 0.0
        var pEinn: [Int: Double] = [:]; var pAusg: [Int: Double] = [:]
        for p in personen { pEinn[p.id] = 0; pAusg[p.id] = 0 }
        for k in karten {
            gEinn += k.geldbetrag
            if let pid = k.personId, pEinn[pid] != nil { pEinn[pid]! += k.geldbetrag }
        }
        for e in kosten {
            if e.istEinnahme { gEinn += e.betrag; if let pid = e.personId, pEinn[pid] != nil { pEinn[pid]! += e.betrag } }
            else { gAusg += e.betrag; if let pid = e.personId, pAusg[pid] != nil { pAusg[pid]! += e.betrag } }
        }
        let gesamtKosten = gAusg - gEinn
        let fair = gesamtKosten / Double(n)
        return personen.map { p in
            let beitrag = (pAusg[p.id] ?? 0) - (pEinn[p.id] ?? 0)
            return (p.name, beitrag - fair)
        }
    }
    var gesamtImbalance: Double { ausgleichSalden.map { abs($0.value) }.reduce(0, +) / 2 }
    var ausgleichszahlungen: [Ausgleichszahlung] {
        var debtors = ausgleichSalden.filter { $0.value < -0.01 }.sorted { $0.value < $1.value }
        var creditors = ausgleichSalden.filter { $0.value > 0.01 }.sorted { $0.value > $1.value }
        var result: [Ausgleichszahlung] = []
        var di = 0, ci = 0, seq = 0
        while di < debtors.count && ci < creditors.count {
            let betrag = min(abs(debtors[di].value), creditors[ci].value)
            if betrag > 0.01 {
                seq += 1
                result.append(Ausgleichszahlung(id: seq, from: debtors[di].name, to: creditors[ci].name, betrag: betrag))
            }
            debtors[di].value += betrag
            creditors[ci].value -= betrag
            if abs(debtors[di].value) < 0.01 { di += 1 }
            if abs(creditors[ci].value) < 0.01 { ci += 1 }
        }
        return result
    }

    // MARK: - Mutationen (Karten)
    func saveKarte(id: Int?, name: String, trauertext: String, geldbetrag: Double, personId: Int?, jpeg: Data?) async -> Bool {
        var body: [String: Any] = ["name": name, "trauertext": trauertext, "geldbetrag": geldbetrag]
        body["person_id"] = personId.map { $0 as Any } ?? NSNull()
        do {
            let cardId: Int
            if let id { try await api.updateKarte(id, body); cardId = id }
            else { cardId = try await api.createKarte(body).id }
            if let jpeg { try await api.attachPhoto(resource: "trauerkarten", id: cardId, jpeg: jpeg) }
            await reloadKarten()
            notify(id == nil ? "Karte gespeichert" : "Gespeichert")
            return true
        } catch { notify(errText(error), error: true); return false }
    }
    func setKartePerson(_ karte: Trauerkarte, _ personId: Int?) async {
        do { try await api.updateKarte(karte.id, ["person_id": personId.map { $0 as Any } ?? NSNull()]); await reloadKarten() }
        catch { notify(errText(error), error: true) }
    }
    func setKarteBetrag(_ karte: Trauerkarte, _ betrag: Double) async {
        do { try await api.updateKarte(karte.id, ["geldbetrag": betrag]); await reloadKarten() }
        catch { notify(errText(error), error: true) }
    }
    func deleteKarte(_ karte: Trauerkarte) async {
        do { try await api.deleteKarte(karte.id); await reloadKarten(); notify("Karte gelöscht") }
        catch { notify(errText(error), error: true) }
    }

    // MARK: - Mutationen (Kosten)
    func saveKosten(id: Int?, beschreibung: String, betrag: Double, istEinnahme: Bool, datum: String, personId: Int?, jpeg: Data?) async -> Bool {
        var body: [String: Any] = ["beschreibung": beschreibung, "betrag": betrag, "ist_einnahme": istEinnahme ? 1 : 0, "datum": datum]
        body["person_id"] = personId.map { $0 as Any } ?? NSNull()
        do {
            let eid: Int
            if let id { try await api.updateKosten(id, body); eid = id }
            else { eid = try await api.createKosten(body).id }
            if let jpeg { try await api.attachPhoto(resource: "trauerkarten-kosten", id: eid, jpeg: jpeg) }
            await reloadKosten()
            notify(id == nil ? "Eintrag hinzugefügt" : "Gespeichert")
            return true
        } catch { notify(errText(error), error: true); return false }
    }
    func deleteKosten(_ e: KostenEintrag) async {
        do { try await api.deleteKosten(e.id); await reloadKosten(); notify("Eintrag gelöscht") }
        catch { notify(errText(error), error: true) }
    }

    // MARK: - Mutationen (Personen)
    func addPerson(_ name: String) async -> Bool {
        do { _ = try await api.createPerson(name); await reloadPersonen(); notify("Person hinzugefügt"); return true }
        catch { notify(errText(error), error: true); return false }
    }
    func renamePerson(_ id: Int, _ name: String) async {
        do { try await api.updatePerson(id, name: name); await reloadPersonen() }
        catch { notify(errText(error), error: true) }
    }
    func deletePerson(_ p: TrauerPerson) async {
        do { try await api.deletePerson(p.id); await reloadPersonen(); await reloadKarten(); await reloadKosten(); notify("Person gelöscht") }
        catch { notify(errText(error), error: true) }
    }

    // MARK: - KI-Scan (token-gated → APIError.status 501)
    func scan(jpeg: Data) async -> [String: Any]? {
        do { return try await api.scan(jpeg: jpeg) }
        catch {
            if let e = error as? APIError, e.status == 501 { notify("KI-Scan ist im Backend nicht konfiguriert.", error: true) }
            else { notify(errText(error), error: true) }
            return nil
        }
    }
}
