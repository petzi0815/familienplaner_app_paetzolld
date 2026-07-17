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

    /// Die Planung des Solvers: warm und/oder kalt. Nie ein "geht nicht" — die Essenszeit ist fix.
    @Published var planung: PizzaPlanung?
    /// Die aktuell gewaehlte Variante. Der Umschalter im Planer schreibt sie ueber `waehleVariante`;
    /// `rechne()` korrigiert sie auf eine tatsaechlich vorhandene, ohne die Nutzerpraeferenz zu aendern.
    @Published var variante: PizzaVariante = .warm
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
    /// aufgehoert hat (Mehltyp/Raumtemperatur/Nachtruhe/Kuehlschrank aendern sich selten). Die
    /// Kuehlschranktemperatur ist Teil von `config` und wird darueber automatisch mitgesichert.
    private static let configKey = "pizza.lastConfig"
    /// Zuletzt vom Nutzer gewaehlte Variante — der Default, wenn beide moeglich sind.
    private static let varianteKey = "pizza.variante"

    init(settings: Settings) {
        api = PizzaAPI(settings: settings)
        config = PizzaStore.gespeicherteConfig()
        essenszeit = PizzaStore.standardEssenszeit()
        variante = PizzaStore.gespeicherteVariante()
        rechne()
    }

    // MARK: - Rechnen

    /// Ruft den Rechenkern mit der aktuellen Uhrzeit. Der Kern selbst bleibt rein — `jetzt`
    /// kommt ausschliesslich von hier. Danach wird `variante` auf eine vorhandene korrigiert:
    /// sind beide moeglich, gilt die (persistierte) Nutzerpraeferenz; sonst die einzig moegliche.
    func rechne() {
        let p = PizzaCalculator.plan(config: config, essen: essenszeit, jetzt: Date())
        planung = p
        if p.warm != nil && p.kalt != nil {
            variante = PizzaStore.gespeicherteVariante()   // beide → zurueck zur Nutzerpraeferenz
        } else if p.warm != nil {
            variante = .warm
        } else if p.kalt != nil {
            variante = .kalt
        }
    }

    /// Der aktuell angezeigte Plan. Faellt auf die jeweils andere Variante zurueck, wenn die
    /// gewaehlte fuer diese Essenszeit nicht existiert (dann zeigt der Planer keinen Umschalter).
    var aktiverPlan: PizzaPlan? {
        guard let p = planung else { return nil }
        switch variante {
        case .warm: return p.warm ?? p.kalt
        case .kalt: return p.kalt ?? p.warm
        }
    }

    /// Beide Varianten vorhanden → der Planer bietet den Umschalter an.
    var beideVarianten: Bool { planung?.warm != nil && planung?.kalt != nil }

    /// Vom Umschalter aufgerufen: setzt die Variante UND merkt sie als Nutzerpraeferenz.
    func waehleVariante(_ v: PizzaVariante) {
        variante = v
        UserDefaults.standard.set(v.rawValue, forKey: PizzaStore.varianteKey)
    }

    /// Kopfzeile des Bereichs: Menge + Startzeit des aktiven Plans (kein Plan → nur die Menge).
    var zusammenfassung: String {
        let menge = "\(String(config.anzahlPizzen)) × \(PizzaCalculator.gramm(config.teiglingsgewichtG)) g"
        if let p = aktiverPlan { return menge + " · Start " + PizzaCalculator.uhrzeit(p.startzeit) }
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

    /// Gemerkte Variante oder — ohne Praeferenz — `.warm` als neutraler Default (kein Erzwingen).
    private static func gespeicherteVariante() -> PizzaVariante {
        guard let raw = UserDefaults.standard.string(forKey: varianteKey),
              let v = PizzaVariante(rawValue: raw) else { return .warm }
        return v
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

    /// Stellt lokale Erinnerungen fuer alle Handgriffe des aktiven Plans (die kalte Variante hat
    /// Handgriffe an mehreren Tagen — `PizzaReminders.plane` terminiert jeden Aktions-Schritt absolut).
    func planeErinnerungen() async {
        guard let p = aktiverPlan else {
            notify("Ohne gültigen Plan gibt es nichts zu erinnern.", error: true)
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
