import SwiftUI
import UIKit

/// Zentraler Zustand des Wein-Bereichs (Weine, Bewertungen, Preis-Historie, Tab/Suche/Filter).
/// Die Liste wird EINMAL geladen und danach clientseitig gefiltert und sortiert — der Keller ist
/// klein genug, und so bleiben Tab-Wechsel und Tippen in der Suche ohne Netz-Rundreise.
/// Weine UND Spirituosen liegen in derselben Liste (eine Tabelle, Begruendung im Kopf von
/// `WeinModels.swift`). Der Umschalter `art` blendet die jeweils andere Getraenkeart aus und wirkt
/// VOR allen uebrigen Filtern — er praegt dadurch auch Kennzahlen, Filterlisten und Sortierung.
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

    /// Angezeigte Getraenkeart (Umschalter im Kopf). Die Wahl ueberlebt den App-Start: wer gerade
    /// die Bar pflegt, will nicht bei jedem Aufruf erst wieder umschalten.
    /// KEIN `@AppStorage` — der Property-Wrapper braucht einen View-Kontext und schreibt in einer
    /// ObservableObject-Klasse nicht zuverlaessig zurueck; deshalb direkt `UserDefaults`, dasselbe
    /// Backing ohne den Wrapper (gleiches Vorgehen wie in `PizzaStore`).
    @Published var art: GetraenkeArt = WeinStore.gespeicherteArt() {
        didSet {
            guard art != oldValue else { return }
            UserDefaults.standard.set(art.rawValue, forKey: WeinStore.artKey)
        }
    }

    private static let artKey = "wein.art"

    /// Zuletzt gewaehlte Art; fehlender oder unbekannter Wert = Wein (der Bestand besteht aus
    /// Weinen, und genau das steht auch als Default in der Migration).
    private static func gespeicherteArt() -> GetraenkeArt {
        GetraenkeArt(rawValue: UserDefaults.standard.string(forKey: artKey) ?? "") ?? .wein
    }

    // Art-eigene Filter: Typ/Rebsorte gelten nur fuer Wein, Kategorie/Stil/Standort nur fuer
    // Spirituosen. Land, Mindeststerne und Sortierung gelten fuer beide.
    @Published var filterTyp: Set<WeinTyp> = []
    @Published var filterKategorie: Set<SpirituosenKategorie> = []
    @Published var filterRebsorte: String?
    @Published var filterStil: String?
    /// nil = alle Standorte (der Eintrag "Alle" im Menue ist genau dieser Fall, kein eigener Wert).
    @Published var filterStandort: WeinStandort?
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
    //
    // ALLE bauen auf `weineDerArt` auf, nicht auf `weine`: die Menues duerfen nur Werte anbieten,
    // die in der angezeigten Liste auch vorkommen. Sonst bliebe unter "Spirituosen" die Rebsorte
    // "Riesling" waehlbar — und die Liste danach kommentarlos leer.

    /// Basis fuer Kennzahlen, Filterlisten und `gefiltert`: nur die gewaehlte Getraenkeart.
    var weineDerArt: [Wein] { weine.filter { $0.art == art } }

    /// Anzahl je Art — die Zaehler am Umschalter (bewusst ueber den GANZEN Bestand, damit die
    /// nicht gewaehlte Seite ihre Zahl auch zeigt).
    func anzahl(_ a: GetraenkeArt) -> Int { weine.filter { $0.art == a }.count }

    var alleRebsorten: [String] {
        Array(Set(weineDerArt.flatMap { $0.rebsorten })).filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var alleLaender: [String] {
        Array(Set(weineDerArt.compactMap { $0.land })).filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Vorhandene Stile — das Spirituosen-Gegenstueck zur Rebsorte ("Single Malt Islay",
    /// "London Dry"), alphabetisch wie dort.
    var alleStile: [String] {
        Array(Set(weineDerArt.compactMap { $0.stil })).filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Vorhandene Kategorien in der Reihenfolge des CHECK (NICHT alphabetisch) — die Filter-Pills
    /// sollen zwischen zwei Aufrufen an derselben Stelle stehen.
    var alleKategorien: [SpirituosenKategorie] {
        let vorhanden = Set(weineDerArt.compactMap { $0.kategorie })
        return SpirituosenKategorie.allCases.filter { vorhanden.contains($0) }
    }

    // MARK: - Warteschlange der Hintergrund-Erkennung
    //
    // Die Zaehler werden aus der GELADENEN Liste abgeleitet und NICHT als eigener Zustand gehalten:
    // das Segment "Queue (n)" und die Liste darunter muessen dieselbe Menge meinen. Ein zweiter,
    // getrennt gepflegter Zaehler koennte der angezeigten Liste widersprechen ("Queue (3)" ueber
    // zwei Zeilen) — der billige Serverzaehler dient deshalb nur als AUSLOESER fuers Nachladen
    // (siehe `queueNachladen()`), nicht als Anzeigewert.
    // Sie folgen wie alles andere dem Umschalter: wer gerade Spirituosen pflegt, sieht auch nur
    // deren offene Erkennungen.

    /// Noch nicht fertig erkannte Flaschen der aktuellen Art, aelteste zuerst.
    /// Die Reihenfolge laeuft ueber die ID: `ki_queued_at` steht nicht im Modell, und die IDs werden
    /// aufsteigend vergeben — die zuerst eingereihte Flasche hat die kleinste. Genau diese
    /// Reihenfolge arbeitet auch der Server ab.
    var queueEintraege: [Wein] {
        weineDerArt.filter { $0.kiStatus != .fertig }.sorted { $0.id < $1.id }
    }

    var queueOffen: Int { weineDerArt.filter { $0.kiStatus == .offen }.count }
    var queueLaeuft: Int { weineDerArt.filter { $0.kiStatus == .laeuft }.count }
    var queueFehler: Int { weineDerArt.filter { $0.kiStatus == .fehler }.count }

    /// Zahl fuer das Segment "Queue (n)". 0 heisst: das Segment erscheint gar nicht — im Alltag
    /// bleibt die Leiste dadurch unveraendert.
    var queueGesamt: Int { queueEintraege.count }

    /// Laeuft gerade ein von Hand angestossener Sammellauf ("Alle jetzt verarbeiten")? Die Ansicht
    /// sperrt den Knopf damit; ein zweiter Anstoss waere nutzlos (der Server laesst ohnehin nur
    /// einen Sammellauf zu) und saehe fuer den Nutzer wie ein Fehler aus.
    @Published private(set) var anreicherungLaeuft = false

    /// Reihenfolge: Art → Tab → Suchtext → art-eigene Filter/Land/Mindeststerne → Sortierung.
    var gefiltert: [Wein] {
        // Die Warteschlange steht BEWUSST vor allem anderen und umgeht Suche, Filter und Sortierung:
        // eine noch nicht erkannte Flasche hat weder Namen noch Land noch Rebsorte, jeder Filter
        // wuerde sie also wegwerfen — und dann waere das Segment leer, obwohl es genau wegen dieser
        // Zeilen ueberhaupt erschienen ist. Auch die Sortierung ist hier fest (aelteste zuerst):
        // abgearbeitet wird von oben, das soll man sehen.
        if tab == .queue { return queueEintraege }

        var out = weineDerArt

        switch tab {
        case .alle:   break
        case .keller: out = out.filter { $0.bestand > 0 }
        case .top:    out = out.filter { (schnitt($0) ?? 0) >= 4 }
        case .offen:  out = out.filter { meine($0) == nil }
        case .queue:  break   // oben schon beantwortet, steht nur der Vollstaendigkeit halber hier
        }

        // Stil und Cocktails sind fuer Spirituosen das, was Rebsorte und Aroma fuer den Wein sind —
        // der Platzhalter des Suchfelds nennt sie, also muessen sie auch getroffen werden.
        let q = suche.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            out = out.filter { w in
                w.name.lowercased().contains(q)
                    || w.weingut.lowercased().contains(q)
                    || (w.region ?? "").lowercased().contains(q)
                    || (w.stil ?? "").lowercased().contains(q)
                    || w.rebsorten.contains { $0.lowercased().contains(q) }
                    || w.aromen.contains { $0.lowercased().contains(q) }
                    || w.cocktails.contains { $0.lowercased().contains(q) }
            }
        }

        // Die art-eigenen Filter greifen NUR bei ihrer Art. Die Filterzeile zeigt je nach Umschalter
        // entweder Weintypen oder Kategorien — ein noch gesetzter Weintyp wuerde die Spirituosen
        // sonst unsichtbar wegfiltern, ohne dass es ein Bedienelement gaebe, ihn wieder zu loesen.
        if art == .wein {
            if !filterTyp.isEmpty { out = out.filter { filterTyp.contains($0.typ) } }
            if let r = filterRebsorte, !r.isEmpty { out = out.filter { $0.rebsorten.contains(r) } }
        } else {
            if !filterKategorie.isEmpty {
                out = out.filter {
                    // Ohne erkannte Kategorie faellt die Flasche aus einem Kategorie-Filter heraus
                    // (nil ist keine Kategorie, auch nicht "sonstiges").
                    guard let k = $0.kategorie else { return false }
                    return filterKategorie.contains(k)
                }
            }
            if let st = filterStil, !st.isEmpty { out = out.filter { $0.stil == st } }
        }
        // Standort gilt seit dem Buero-Ausbau fuer BEIDE Arten: das Menue dazu steht jetzt in der
        // Dropdown-Zeile von Wein wie Spirituose, ein gesetzter Filter ist also ueberall zu sehen
        // und zu loesen. Vorher stand er im Spirituosen-Zweig — unter "Weine" haette er unsichtbar
        // weitergefiltert.
        if let so = filterStandort { out = out.filter { $0.standort == so } }
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
                switch (jahrgangSortwert(a), jahrgangSortwert(b)) {
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

    /// Sortierwert des Falls `.jahrgang`: Spirituosen tragen keinen Jahrgang, sondern eine
    /// Altersangabe — dort sortiert derselbe Fall nach `alterJahre`. Der Jahrgang bleibt als
    /// Rueckfall stehen, falls doch einer erfasst wurde (z. B. bei einer Single-Cask-Abfuellung).
    /// Entschieden wird je Flasche, nicht ueber `art` des Stores: so stimmt die Sortierung auch,
    /// wenn die Liste einmal gemischt vorliegt.
    private func jahrgangSortwert(_ w: Wein) -> Int? {
        w.art == .spirituose ? (w.alterJahre ?? w.jahrgang) : w.jahrgang
    }

    /// Filter/Suche zuruecksetzen (Knopf im Filter-Sheet). Raeumt BEIDE Arten — der Knopf soll
    /// wirklich alles loesen, nicht nur das gerade Sichtbare.
    func filterZuruecksetzen() {
        filterTyp = []
        filterKategorie = []
        filterRebsorte = nil
        filterStil = nil
        filterStandort = nil
        filterLand = nil
        filterMinSterne = nil
        suche = ""
    }

    /// Es zaehlen nur die Filter, die `gefiltert` bei der aktuellen Art auch anwendet. Sonst
    /// meldete die Leerzustands-Karte unter "Spirituosen" einen aktiven Filter, den man dort weder
    /// sieht noch loesen kann.
    var filterAktiv: Bool {
        let artEigen = art == .wein
            ? (!filterTyp.isEmpty || filterRebsorte != nil)
            : (!filterKategorie.isEmpty || filterStil != nil)
        // Standort zaehlt jetzt bei beiden Arten mit — er wirkt bei beiden und ist bei beiden
        // bedienbar (siehe `gefiltert`).
        return artEigen || filterStandort != nil || filterLand != nil || filterMinSterne != nil
    }

    // MARK: - Mutationen

    /// Anlegen (id == nil) oder aendern. Gibt die ID des gespeicherten Weins zurueck, nil bei Fehler.
    @discardableResult
    func save(_ fields: [String: Any], id: Int?) async -> Int? {
        do {
            let w: Wein
            if let id { w = try await api.update(id, fields) } else { w = try await api.create(fields) }
            ersetzeOderErgaenze(w)
            // Die Art kommt aus der ANTWORT, nicht aus dem Umschalter: gespeichert ist, was der
            // Server zurueckgibt ("Spirituose gespeichert"). Fehlt sie, ist es laut Modell ein Wein
            // — dann steht hier derselbe Satz wie vor Migration 0022.
            notify(id == nil ? w.art.einzahl + " gespeichert" : "Änderungen gespeichert")
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
    /// Der Rueckgabewert sagt, ob der Server es angenommen hat — die Wisch-Aktionen haengen ihre
    /// Erfolgsmeldung daran. Aus dem Store-Zustand allein waere das nicht ablesbar: nach dem
    /// Zurueckdrehen sieht ein Fehlschlag genauso aus wie ein Aufruf, bei dem sich nichts geaendert hat.
    @discardableResult
    func setBestand(_ wein: Wein, _ n: Int) async -> Bool {
        let neu = max(0, n)
        let alt = wein.bestand
        guard neu != alt else { return true }
        patchLokal(wein.id) { $0.bestand = neu }
        do {
            let w = try await api.update(wein.id, ["bestand": neu])
            ersetzeOderErgaenze(w)
            return true
        } catch {
            patchLokal(wein.id) { $0.bestand = alt }
            notify(errText(error), error: true)
            return false
        }
    }

    /// Eine Flasche entnehmen (Wisch-Aktion). Nie unter 0 — das erledigt schon `setBestand`, hier
    /// steht zusaetzlich der Klartext davor, damit ein Wisch auf einen leeren Eintrag nicht wirkungslos
    /// aussieht.
    func bestandMinusEins(_ wein: Wein) async {
        guard wein.bestand > 0 else {
            notify("Es ist keine Flasche mehr verbucht", error: true)
            return
        }
        let neu = wein.bestand - 1
        if await setBestand(wein, neu) { notify(WeinStore.bestandsMeldung(neu)) }
    }

    /// Ganzen Bestand auf 0 setzen (Wisch-Aktion "Leer"). Die Flasche bleibt im Inventar — mit
    /// Bewertung, Preis-Historie und Foto; sie faellt nur aus dem Keller. Wer sie wirklich loswerden
    /// will, loescht sie.
    func leeren(_ wein: Wein) async {
        guard wein.bestand > 0 else {
            notify("Es ist keine Flasche mehr verbucht", error: true)
            return
        }
        if await setBestand(wein, 0) { notify("Als leer markiert") }
    }

    /// Rueckmeldung nach dem Entnehmen. Bewusst mit Einzahl/Mehrzahl und einem eigenen Satz fuer 0:
    /// "Noch 1 Flaschen" oder "Noch 0 Flaschen" waere beides falsch.
    private static func bestandsMeldung(_ rest: Int) -> String {
        switch rest {
        case 0:  return "Letzte Flasche entnommen"
        case 1:  return "Noch 1 Flasche"
        default: return "Noch \(String(rest)) Flaschen"
        }
    }

    /// Groben Fuellstand setzen (0..100; nil = nicht erfasst), optimistisch wie `setBestand`.
    /// BEWUSST OHNE Erfolgsmeldung: der Wert wird ueber einen Stufen-Picker gesetzt und wuerde
    /// sonst bei jedem Schritt einen Toast werfen — der Balken selbst ist die Rueckmeldung.
    func setFuellstand(_ wein: Wein, _ prozent: Int?) async {
        // Geklemmt auf den Wertebereich des CHECK (BETWEEN 0 AND 100) — ein Ausreisser waere sonst
        // erst am 422 des Servers zu merken.
        let neu = prozent.map { max(0, min(100, $0)) }
        let alt = wein.fuellstandProzent
        guard neu != alt else { return }
        patchLokal(wein.id) { $0.fuellstandProzent = neu }
        do {
            let body: [String: Any] = ["fuellstand_prozent": neu ?? NSNull()]
            let w = try await api.update(wein.id, body)
            ersetzeOderErgaenze(w)
        } catch {
            patchLokal(wein.id) { $0.fuellstandProzent = alt }
            notify(errText(error), error: true)
        }
    }

    /// Flasche oeffnen bzw. wieder als ungeoeffnet markieren (optimistisch wie `setBestand`).
    /// Beim Oeffnen wird zusaetzlich der Fuellstand auf 100 gesetzt — aber NUR, wenn noch keiner
    /// erfasst ist: eine gerade geoeffnete Flasche ist voll. Ein bereits gepflegter Wert bleibt
    /// stehen, sonst machte ein versehentliches Zurueck-und-wieder-Oeffnen aus der halb leeren
    /// Flasche wieder eine volle.
    /// Anders als beim Fuellstand gibt es hier eine Erfolgsmeldung (wie bei `setBeobachten`): der
    /// Schalter aendert nur eine Beschriftung, die Rueckmeldung samt Haptik kommt aus `notify`.
    func setAngebrochen(_ wein: Wein, _ offen: Bool) async {
        guard offen != wein.istAngebrochen else { return }
        let altDatum = wein.angebrochenAt
        let altFuellstand = wein.fuellstandProzent
        let neuDatum: String? = offen ? WeinStore.heuteISO() : nil
        let neuFuellstand: Int? = (offen && altFuellstand == nil) ? 100 : altFuellstand

        patchLokal(wein.id) {
            $0.angebrochenAt = neuDatum
            $0.fuellstandProzent = neuFuellstand
        }
        do {
            var body: [String: Any] = ["angebrochen_at": neuDatum ?? NSNull()]
            // Den Fuellstand nur mitschicken, wenn er sich wirklich aendert — sonst ueberschriebe
            // das Schliessen den gepflegten Wert mit sich selbst.
            if neuFuellstand != altFuellstand { body["fuellstand_prozent"] = neuFuellstand ?? NSNull() }
            let w = try await api.update(wein.id, body)
            ersetzeOderErgaenze(w)
            notify(offen ? "Flasche geöffnet" : "Als ungeöffnet markiert")
        } catch {
            patchLokal(wein.id) {
                $0.angebrochenAt = altDatum
                $0.fuellstandProzent = altFuellstand
            }
            notify(errText(error), error: true)
        }
    }

    /// Heutiges Datum als "yyyy-MM-dd" — genau die Form, die in `angebrochen_at` steht und die
    /// `WeinFormat.datum` wieder lesen kann. Bewusst Ortszeit: "heute" ist der Tag des Nutzers,
    /// nicht der von UTC (sonst waere eine Flasche, die um 23 Uhr geoeffnet wird, von morgen).
    private static func heuteISO() -> String { isoTag.string(from: Date()) }

    private static let isoTag: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    /// Flasche im Buero parken bzw. wieder nach Hause holen (optimistisch wie `setBestand`).
    /// Es aendert sich AUSSCHLIESSLICH das Gebaeude: Bestand, `lagerort` und alles uebrige bleiben
    /// stehen — eine geparkte Flasche verschwindet nirgends, sie traegt nur zusaetzlich ein Label.
    /// Mit Erfolgsmeldung wie bei `setBeobachten`: der Knopf tauscht bloss seine Beschriftung, die
    /// spuerbare Rueckmeldung samt Haptik kommt aus `notify`.
    func setStandort(_ wein: Wein, _ standort: WeinStandort) async {
        let alt = wein.standort
        guard standort != alt else { return }
        patchLokal(wein.id) { $0.standort = standort }
        do {
            // Gezielt nur diese eine Spalte — der volle `patchFields` schriebe den ganzen Datensatz
            // zurueck und ueberschriebe dabei, was inzwischen woanders geaendert wurde.
            let w = try await api.update(wein.id, ["standort": standort.rawValue])
            ersetzeOderErgaenze(w)
            notify(standort == .buero ? "Im Büro geparkt" : "Wieder zu Hause")
        } catch {
            patchLokal(wein.id) { $0.standort = alt }
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
            entferneLokal(wein.id)
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

    // MARK: - Schnellerfassung und Warteschlange

    /// Flasche einreihen: Etikettenfoto ODER Barcode rein, der Server legt die Zeile SOFORT an und
    /// erkennt sie im Hintergrund. `art` geht immer als Hinweis mit (der Umschalter der Ansicht) —
    /// widerspricht das Etikett, gewinnt laut Backend die Erkennung.
    ///
    /// `serie` ist der Serienmodus (Kamera bleibt offen, ein Barcode nach dem anderen): dort wird
    /// WEDER nachgeladen NOCH gemeldet. Die Ansicht zaehlt selbst und fasst am Ende alles in einem
    /// Toast zusammen; ein Nachladen je Ausloesung waere eine volle Liste pro Foto, und ein Toast je
    /// Ausloesung wuerde die Rueckmeldung ueberschreiben, die der Nutzer gerade lesen soll.
    /// Der Rueckgabewert ist die Grundlage dieser Zaehlung — ein fehlgeschlagener Upload (Flugmodus)
    /// darf nicht still verschwinden.
    @discardableResult
    func erfassen(image: Data? = nil, ean: String? = nil, standort: WeinStandort? = nil,
                  lagerort: String? = nil, serie: Bool = false) async -> Bool {
        do {
            _ = try await api.erfassen(image: image, ean: ean, art: art,
                                       standort: standort, lagerort: lagerort)
            if !serie {
                await reload()
                notify(art.einzahl + " eingereiht — wird jetzt erkannt")
            }
            return true
        } catch {
            if !serie { notify(errText(error), error: true) }
            return false
        }
    }

    /// Erkennung anstossen: ohne `id` alles Offene der Reihe nach ("Alle jetzt verarbeiten"), mit
    /// `id` genau diese eine Flasche ("Erneut versuchen", "Erneut erkennen lassen") — die ignoriert
    /// serverseitig auch die Versuchsgrenze.
    /// Laeuft minutenlang; danach wird die Liste nachgezogen, damit die frisch erkannten Flaschen
    /// mit Namen dastehen.
    func anreicherungStarten(id: Int? = nil) async {
        // Nicht still verschlucken: wer waehrend eines Laufs noch einmal tippt, bekommt gesagt,
        // warum nichts passiert. Ein zweiter Anstoss brauchte ohnehin nicht anzukommen — der Server
        // laesst nur einen Sammellauf gleichzeitig zu.
        guard !anreicherungLaeuft else {
            notify("Es läuft schon eine Erkennung")
            return
        }
        anreicherungLaeuft = true
        defer { anreicherungLaeuft = false }
        do {
            let lauf = try await api.anreicherungStarten(id: id)
            await reload()
            notify(WeinStore.laufMeldung(verarbeitet: lauf.verarbeitet, fertig: lauf.fertig, fehler: lauf.fehler),
                   error: lauf.verarbeitet > 0 && lauf.fertig == 0)
        } catch {
            // Klartext des Backends stehen lassen (fehlender Schluessel = 501, Anbieter nicht
            // erreichbar = 502) — eine Pauschalmeldung liesse den Fehler bei der Flasche suchen.
            notify(errText(error), error: true)
        }
    }

    /// Ergebnis eines Laufs in einem Satz. Jede Zahl wird ueber `String(...)` gesetzt (sonst macht
    /// die Interpolation aus 1024 ein "1.024"), und jede Form muss auch bei 1 und bei 0 stimmen.
    private static func laufMeldung(verarbeitet: Int, fertig: Int, fehler: Int) -> String {
        if verarbeitet == 0 { return "Gerade ist nichts zu erkennen" }
        if fehler == 0 { return fertig == 1 ? "1 Flasche erkannt" : "\(String(fertig)) Flaschen erkannt" }
        if fertig == 0 { return fehler == 1 ? "Erkennung fehlgeschlagen" : "\(String(fehler)) Flaschen nicht erkannt" }
        return "\(String(fertig)) erkannt, \(String(fehler)) fehlgeschlagen"
    }

    /// Zaehlerstand der Warteschlange beim Server holen und die Liste NUR nachziehen, wenn sich
    /// wirklich etwas bewegt hat. Genau dafuer gibt es die schmale GET-Route: die Ansicht ruft das
    /// im Sekundentakt, solange die Queue nicht leer und sichtbar ist — eine volle Liste alle zehn
    /// Sekunden waere Verschwendung.
    /// BEWUSST OHNE eigenen Timer im Store: ein Timer hier liefe auch weiter, wenn der Bereich gar
    /// nicht mehr sichtbar ist. Das Takten gehoert zur Ansicht (`scenePhase`), sie ist die Einzige,
    /// die weiss, ob gerade jemand hinschaut.
    /// Fehler bleiben stumm — ein kurzer Netzhaenger beim Nachzaehlen ist keine Meldung wert und
    /// wuerde alle zehn Sekunden dieselbe Fehlerblase erzeugen.
    func queueNachladen() async {
        guard let z = try? await api.queueZaehler(art: art) else { return }
        if z.offen != queueOffen || z.laeuft != queueLaeuft || z.fehler != queueFehler {
            await reload()
        }
    }

    /// Nicht erkannte Flasche wegwerfen (Knopf "Verwerfen" in der Queue). Loescht die Zeile — bei
    /// einem Fehlauslöser der Kamera ist genau das gemeint, und der Datensatz enthaelt ausser dem
    /// Foto ohnehin nichts.
    /// Eigene Meldung statt `delete`: dort steht "Gelöscht", was nach einem Verlust klingt.
    func verwerfen(_ wein: Wein) async {
        do {
            try await api.delete(wein.id)
            entferneLokal(wein.id)
            notify("Verworfen")
        } catch {
            notify(errText(error), error: true)
        }
    }

    // MARK: - Lokaler Cache

    private func patchLokal(_ id: Int, _ mutate: (inout Wein) -> Void) {
        if let i = weine.firstIndex(where: { $0.id == id }) { mutate(&weine[i]) }
    }

    private func ersetzeOderErgaenze(_ w: Wein) {
        guard w.id > 0 else { return }
        if let i = weine.firstIndex(where: { $0.id == w.id }) { weine[i] = w } else { weine.insert(w, at: 0) }
    }

    /// Zeile samt allem, was an ihrer ID haengt, aus dem lokalen Stand nehmen. Bewertungen und
    /// Preis-Historie MUESSEN mit weg: sonst zeigte eine spaeter mit derselben ID neu angelegte
    /// Flasche die Sterne ihrer Vorgaengerin.
    private func entferneLokal(_ id: Int) {
        weine.removeAll { $0.id == id }
        bewertungen[id] = nil
        preise[id] = nil
    }

    // notify(_:error:) und errText(_:) kommen aus NotifiableStore.
}
