import SwiftUI

/// Zentraler Zustand des Pizza-Bereichs: Eingaben (`config` + `essenszeit`), das daraus gerechnete
/// `ergebnis` und die gespeicherten Rezepturen/Notizen.
///
/// Jede Aenderung an `config`/`essenszeit` rechnet sofort neu (`didSet` → `rechne()`), damit die
/// Views nie selbst an den Rechenkern denken muessen: sie binden an die Eingaben und lesen `ergebnis`.
@MainActor
final class PizzaStore: ObservableObject, NotifiableStore {
    let api: PizzaAPI

    // MARK: - Eingaben (loesen die Neuberechnung aus)

    @Published var config: PizzaConfig { didSet { if config != oldValue { configGeaendert() } } }
    @Published var essenszeit: Date { didSet { if essenszeit != oldValue { rechne() } } }

    // MARK: - Ergebnis + Ansicht

    /// Plan ODER Problem — beides sind Anzeigezustaende, nie eine Exception.
    @Published var ergebnis: PizzaErgebnis?
    @Published var tab: PizzaTab = .planer
    @Published var showAdvanced = false

    // MARK: - Rezepturen

    @Published var rezepte: [PizzaRezept] = []
    /// Notizen je Rezeptur-id — werden erst beim Aufklappen geladen (`loadNotizen`).
    @Published var notizen: [Int: [PizzaNotiz]] = [:]
    @Published var loading = true

    // MARK: - Toast (NotifiableStore)

    @Published var message: String?
    @Published var messageIsError = false

    /// Letzte Konfiguration — der Planer soll nach einem Neustart dort weitermachen, wo Lars
    /// aufgehoert hat (Mehltyp/Raumtemperatur/Nachtruhe aendern sich selten).
    private static let configKey = "pizza.lastConfig"

    init(settings: Settings) {
        api = PizzaAPI(settings: settings)
        config = PizzaStore.gespeicherteConfig()
        essenszeit = PizzaStore.standardEssenszeit()
        rechne()
    }

    // MARK: - Rechnen

    /// Ruft den Rechenkern mit der aktuellen Uhrzeit. Der Kern selbst bleibt rein — `jetzt`
    /// kommt ausschliesslich von hier.
    func rechne() {
        ergebnis = PizzaCalculator.plan(config: config, essen: essenszeit, jetzt: Date())
    }

    /// Bequemer Zugriff fuer die Views (statt ueberall `switch` zu schreiben).
    var plan: PizzaPlan? { ergebnis?.erfolg }
    var problem: PizzaProblem? { ergebnis?.problem }

    /// Kopfzeile des Bereichs: Menge + Startzeit, bei einem Problem dessen Titel.
    var zusammenfassung: String {
        let menge = "\(String(config.anzahlPizzen)) × \(PizzaCalculator.gramm(config.teiglingsgewichtG)) g"
        if let p = plan { return menge + " · Start " + PizzaCalculator.uhrzeit(p.startzeit) }
        if let f = problem { return f.titel }
        return menge
    }

    private func configGeaendert() {
        sichereConfig()
        rechne()
    }

    // MARK: - Persistenz der letzten Konfiguration
    //
    // Ein Store kann @AppStorage nicht sinnvoll nutzen (Property-Wrapper ohne View-Kontext),
    // deshalb direkt UserDefaults — dasselbe Backing, nur ohne den Wrapper.

    private func sichereConfig() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: PizzaStore.configKey)
    }

    /// Gespeicherte Config oder der Standard. Ein aelterer/kaputter Datensatz faellt still auf
    /// den Standard zurueck — eine Voreinstellung ist nichts, wofuer man den Nutzer behelligt.
    private static func gespeicherteConfig() -> PizzaConfig {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let c = try? JSONDecoder().decode(PizzaConfig.self, from: data) else { return .standard }
        return c.normalisiert()
    }

    /// Vorschlag beim Start: das naechste 18-Uhr-Abendessen, das noch mindestens 4,5 h entfernt ist.
    static func standardEssenszeit(jetzt: Date = Date(), calendar: Calendar = .current) -> Date {
        let frueheste = calendar.date(byAdding: .minute, value: PizzaKonstanten.minVorlaufMin, to: jetzt)
            ?? jetzt.addingTimeInterval(Double(PizzaKonstanten.minVorlaufMin) * 60)
        var kandidat = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: jetzt) ?? frueheste
        var runden = 0
        while kandidat < frueheste && runden < 7 {
            kandidat = calendar.date(byAdding: .day, value: 1, to: kandidat) ?? frueheste
            runden += 1
        }
        return max(kandidat, frueheste)
    }

    // MARK: - Rezepturen laden

    func loadRezepte() async {
        loading = true
        rezepte = (try? await api.fetchRezepte()) ?? []
        loading = false
    }

    func loadNotizen(_ rezeptId: Int) async {
        if let n = try? await api.fetchNotizen(rezeptId: rezeptId) { notizen[rezeptId] = n }
    }

    var favoriten: [PizzaRezept] { rezepte.filter(\.favorit) }

    // MARK: - Rezepturen aendern

    /// Speichert die AKTUELLE Konfiguration unter einem Namen.
    @discardableResult
    func speichereAlsRezept(name: String, notiz: String? = nil) async -> Bool {
        let sauber = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sauber.isEmpty else { notify("Bitte einen Namen angeben.", error: true); return false }
        do {
            _ = try await api.createRezept(PizzaRezept(from: config, name: sauber, notiz: notiz).body)
            await loadRezepte()
            notify("Rezeptur gespeichert")
            return true
        } catch { notify(errText(error), error: true); return false }
    }

    /// Uebernimmt die Rezeptur in den Planer (Essenszeit bleibt, die gehoert nicht zur Rezeptur).
    func ladeRezept(_ r: PizzaRezept) {
        config = r.config          // didSet → sichern + neu rechnen
        tab = .planer
        notify("Rezeptur geladen: " + r.name)
    }

    /// Ueberschreibt eine Rezeptur mit der aktuellen Konfiguration.
    @discardableResult
    func aktualisiereRezept(_ r: PizzaRezept, name: String? = nil, notiz: String? = nil) async -> Bool {
        let neu = PizzaRezept(from: config, name: name ?? r.name, favorit: r.favorit, notiz: notiz ?? r.notiz)
        do {
            try await api.updateRezept(r.id, neu.body)
            await loadRezepte()
            notify("Rezeptur aktualisiert")
            return true
        } catch { notify(errText(error), error: true); return false }
    }

    func toggleFavorit(_ r: PizzaRezept) async {
        do {
            try await api.updateRezept(r.id, ["favorit": r.favorit ? 0 : 1])
            await loadRezepte()
        } catch { notify(errText(error), error: true) }
    }

    func loescheRezept(_ r: PizzaRezept) async {
        do {
            try await api.deleteRezept(r.id)
            notizen[r.id] = nil     // die Notizen sind serverseitig per CASCADE schon weg
            await loadRezepte()
            notify("Rezeptur gelöscht")
        } catch { notify(errText(error), error: true) }
    }

    // MARK: - Notizen

    /// `bewertung` wird auf 1…5 begrenzt — das Backend hat dort einen CHECK und wuerde sonst 422 werfen.
    @discardableResult
    func addNotiz(rezeptId: Int, text: String, bewertung: Int?, gebackenAm: Date? = nil) async -> Bool {
        let sauber = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sauber.isEmpty else { notify("Bitte einen Text eingeben.", error: true); return false }
        var b: [String: Any] = [
            "rezept_id": rezeptId,
            "text": sauber,
            "gebacken_am": PizzaText.isoDatum(gebackenAm ?? Date()),
        ]
        b["bewertung"] = bewertung.map { min(max($0, 1), 5) as Any } ?? NSNull()
        do {
            _ = try await api.createNotiz(b)
            await loadNotizen(rezeptId)
            notify("Notiz gespeichert")
            return true
        } catch { notify(errText(error), error: true); return false }
    }

    func loescheNotiz(_ n: PizzaNotiz) async {
        do {
            try await api.deleteNotiz(n.id)
            await loadNotizen(n.rezeptId)
            notify("Notiz gelöscht")
        } catch { notify(errText(error), error: true) }
    }

    // MARK: - Erinnerungen

    /// Stellt lokale Erinnerungen fuer alle Handgriffe des aktuellen Plans.
    func planeErinnerungen() async {
        guard let p = plan else {
            notify(problem?.titel ?? "Ohne gültigen Plan gibt es nichts zu erinnern.", error: true)
            return
        }
        let n = await PizzaReminders.plane(plan: p)
        if n > 0 { notify("\(String(n)) Erinnerungen gestellt") }
        else { notify("Keine Erinnerung gestellt – bitte Mitteilungen erlauben.", error: true) }
    }

    func loescheErinnerungen() async {
        await PizzaReminders.loesche()
        notify("Erinnerungen entfernt")
    }
}
