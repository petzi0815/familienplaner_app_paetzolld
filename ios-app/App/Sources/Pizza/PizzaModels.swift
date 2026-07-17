import Foundation

// Datenmodelle des Pizza-Planers (neapolitanischer Teig, Rueckwaertsplanung ab der Essenszeit).
//
// Bewusst SwiftUI-frei: der Rechenkern soll ohne UI-Stack deterministisch testbar bleiben.
// Ofentyp ist KEIN Parameter - fest verbaut ist der Gozney Dome (Gas), daher vorheizMin = 30.

// MARK: - Konstanten

/// Alle Konstanten des Berechnungsmodells an einer Stelle, damit Views/Tests dieselben Grenzen
/// benutzen wie der Rechenkern (und niemand Zahlen doppelt pflegt).
enum PizzaKonstanten {
    static let salzAnteil = 0.028
    static let zielTeigtempC = 24.0

    /// Gozney Dome (Gas). Ofentyp ist fix, deshalb eine Konstante und kein Eingabefeld.
    static let vorheizMin = 30

    static let fixKneten = 15
    static let fixEntspannen = 15
    static let fixPortionieren = 15
    static let fixBacken = 10
    /// Summe der vier Fixbloecke; die Gare (netto) kommt obendrauf.
    static let fixSumme = 55

    static let stockAnteil = 0.35
    static let stueckAnteil = 0.65
    static let stockMin = 60
    static let stueckMin = 120

    /// 4,5 h Gesamtfenster minus Fixbloecke.
    static let nettoMin = 215
    /// 12 h Praxisfenster fuer Raumtemperatur-Gare.
    static let nettoMax = 720
    /// 6-h-Standardplan minus Fixbloecke.
    static let nettoStandard = 305

    static let hefePctMin = 0.05
    static let hefePctMax = 0.8
    static let kDefault = 4.5

    // MARK: Kalte Kuehlschrankgare (Kugeln kalt, ueber Nacht)
    //
    // Ablauf: kneten -> kurze warme Stockgare (bulk) -> formen -> KUEHLSCHRANK (passiv, ueber
    // Nacht) -> morgens rausnehmen + anwaermen/Stueckgare (appretto) -> backen.
    /// Kuehlschranktemperatur (Advanced 2-10 C); 5 C = uebliche Haushaltseinstellung.
    static let fridgeTempDefault = 5.0
    static let fridgeTempMin = 2.0
    static let fridgeTempMax = 10.0
    /// Warme Stockgare vor dem Kuehlschrank (min).
    static let bulkIdeal = 120
    static let bulkMin = 60
    static let bulkMax = 240
    /// Anwaermen + Stueckgare nach dem Kuehlschrank (min). appFloor = absolute Notgrenze.
    static let apprettoIdeal = 180
    static let apprettoMin = 120
    static let apprettoMax = 300
    static let apprettoFloor = 30
    /// Kuehlschrankgare selbst: 8 h bis 72 h.
    static let fridgeGareMin = 8 * 60
    static let fridgeGareMax = 72 * 60

    static let hydrationMin = 0.55
    static let hydrationMax = 0.70

    static let anzahlMin = 1
    static let anzahlMax = 12
    static let gewichtMin = 200.0
    static let gewichtMax = 320.0
    static let raumtempMin = 17.0
    static let raumtempMax = 28.0
    static let mehltempMin = 5.0
    static let mehltempMax = 30.0
    static let wasserTempMin = 5.0
    static let wasserTempMax = 35.0

    /// Semola zum Ausbreiten - Faustregel, nicht Teil des Formelwerks (geht nicht in den Teig ein).
    /// Auf die Referenzkonfiguration der Spec geeicht: 6 Teiglinge -> rund 100 g (§6.1).
    static let semolaProTeiglingG = 16.7

    /// Kuerzestmoeglicher Vorlauf vom ersten Handgriff bis zur Pizza = 4,5 h.
    static let minVorlaufMin = fixSumme + nettoMin

    /// Nachtruhe-Default: 23:00 bis 07:00 (Minuten seit Mitternacht).
    static let schlafVonDefault = 23 * 60
    static let schlafBisDefault = 7 * 60

    static let minutenProTag = 1440
}

// MARK: - Aufzaehlungen

enum Mehltyp: String, CaseIterable, Codable {
    // Reihenfolge = Picker-Reihenfolge. rawValues bleiben abwaertskompatibel:
    // 'tipo00'/'dinkel' existieren in gespeicherten Rezepten. Die drei neuen sind alle
    // Weizen-Tipo-00 (mehlFaktor 1.0) - gleiche Gaergeschwindigkeit wie tipo00, also gleiche
    // Hefemenge; sie unterscheiden sich nur in hydrationDefault und der Gaer-Toleranz.
    case tipo00
    case caputo_pizzeria
    case la_farina_14
    case edeka_herzstuecke
    case dinkel

    var label: String {
        switch self {
        case .tipo00: return "Tipo 00 (Standard)"
        case .caputo_pizzeria: return "Caputo Pizzeria"
        case .la_farina_14: return "La Farina 14"
        case .edeka_herzstuecke: return "Edeka Herzstücke"
        case .dinkel: return "Dinkel 630"
        }
    }

    /// Protein-/W-Wert zur Anzeige in der Mehlauswahl (keine Rechengroesse).
    var proteinInfo: String {
        switch self {
        case .tipo00: return "~12,5 %"
        case .caputo_pizzeria: return "12,5 % · W 260–270"
        case .la_farina_14: return "14 %"
        case .edeka_herzstuecke: return "13 %"
        case .dinkel: return "—"
        }
    }

    var hydrationDefault: Double {
        switch self {
        case .tipo00: return 0.625
        case .caputo_pizzeria: return 0.625
        case .la_farina_14: return 0.66
        case .edeka_herzstuecke: return 0.61
        case .dinkel: return 0.59
        }
    }

    /// Gaermodell: nur Dinkel treibt traeger (braucht bei gleicher Zeit mehr Hefe). Die drei
    /// neuen Weizenmehle garen wie tipo00 - der Faktor 1.0 haelt die Hefemenge unveraendert.
    var mehlFaktor: Double {
        switch self {
        case .tipo00, .caputo_pizzeria, .la_farina_14, .edeka_herzstuecke: return 1.0
        case .dinkel: return 1.1
        }
    }

    /// Untere Grenze des sinnvollen Gaerfensters (Wanduhr-Stunden), bevor das Aroma zu kurz kommt.
    var idealFermMinStunden: Double {
        switch self {
        case .tipo00: return 6
        case .caputo_pizzeria: return 8
        case .la_farina_14: return 24
        case .edeka_herzstuecke: return 8
        case .dinkel: return 4
        }
    }

    /// Obere Grenze des Gaerfensters (Wanduhr-Stunden), ab der der Kleber nachlaesst.
    var idealFermMaxStunden: Double {
        switch self {
        case .tipo00: return 48
        case .caputo_pizzeria: return 48
        case .la_farina_14: return 72
        case .edeka_herzstuecke: return 36
        case .dinkel: return 12
        }
    }

    /// Ein Satz fuer die Mehlauswahl: was zeichnet das Mehl aus?
    var charakter: String {
        switch self {
        case .tipo00: return "Generischer Tipo-00-Standard – verhält sich wie bisher."
        case .caputo_pizzeria: return "Verzeiht Fehler, stabil bei kurzer–mittlerer Gare."
        case .la_farina_14: return "Stark, nimmt viel Wasser – für lange, kalte Gare (24–72 h)."
        case .edeka_herzstuecke: return "Supermarkt-Allrounder, luftig-knusprig."
        case .dinkel: return "Überknetet schnell – dehnen & falten, kürzere Gare."
        }
    }

    /// Nur Dinkel braucht eine Knet-Warnung - sein Klebergeruest vertraegt kein langes Kneten.
    /// Die Weizen-Tipo-00 sind unkritisch.
    var knetHinweis: String? {
        switch self {
        case .tipo00, .caputo_pizzeria, .la_farina_14, .edeka_herzstuecke: return nil
        case .dinkel: return "Dinkel nicht überkneten – der Kleber reißt sonst und der Teig wird krümelig."
        }
    }

    func knetzeitText(_ methode: Knetmethode) -> String {
        switch (self, methode) {
        // La Farina 14 ist staerker und vertraegt etwas laengeres Kneten.
        case (.la_farina_14, .maschine): return "12-15 Min. Maschine"
        case (.dinkel, .maschine): return "6-8 Min. Maschine"
        case (.dinkel, .hand): return "10-12 Min. Hand"
        // Die uebrigen Weizen-Tipo-00 (inkl. tipo00) kneten wie bisher.
        case (_, .maschine): return "10-12 Min. Maschine"
        case (_, .hand): return "15-20 Min. Hand"
        }
    }
}

enum Hefetyp: String, CaseIterable, Codable {
    case frisch
    case trocken

    var label: String {
        switch self {
        case .frisch: return "Frischhefe"
        case .trocken: return "Trockenhefe"
        }
    }

    /// Verarbeitung im Wasser (Spec §3.3). Trockenhefe braucht Vorlauf, sonst bleiben Koerner
    /// im Teig und die Gaerung startet ungleichmaessig.
    var aufloesHinweis: String {
        switch self {
        case .frisch: return "Frischhefe direkt im Wasser auflösen."
        case .trocken: return "Trockenhefe vollständig im Wasser auflösen, 5 Min. warten."
        }
    }
}

enum Knetmethode: String, CaseIterable, Codable {
    case maschine
    case hand

    var label: String {
        switch self {
        case .maschine: return "Maschine"
        case .hand: return "Hand"
        }
    }

    /// Reibungswaerme, die der Knetvorgang in den Teig eintraegt (geht in die Wassertemperatur ein).
    var reibung: Double {
        switch self {
        case .maschine: return 6.0
        case .hand: return 2.0
        }
    }
}

/// Die beiden Planvarianten, die der Solver anbietet. Die Essenszeit ist immer fix - variiert
/// werden Hefemenge, Gaerzeiten und (bei kalt) die Kuehlschrankgare ueber Nacht.
enum PizzaVariante: String, Codable, CaseIterable {
    case warm
    case kalt

    var label: String {
        switch self {
        case .warm: return "Schnell · warm"
        case .kalt: return "Über Nacht · kalt"
        }
    }

    /// Ein Satz, der die Variante in der UI erklaert.
    var kurzErklaerung: String {
        switch self {
        case .warm:
            return "Same-Day: alles an einem Tag bei Raumtemperatur gegärt."
        case .kalt:
            return "Kugeln reifen über Nacht im Kühlschrank – mehr Aroma und deutlich weniger Hefe."
        }
    }
}

// MARK: - Eingabe

/// Alle Eingabeparameter eines Plans.
///
/// Nachtruhe als **Minuten seit Mitternacht** (Int), nicht als "HH:mm"-String:
/// der Solver prueft pro Kandidat mehrere Zeitpunkte gegen das Fenster, das sind bis zu
/// fuenfstellig viele Vergleiche - Int-Arithmetik modulo 1440 ist dabei exakt, allokationsfrei
/// und kann nicht am Parsen scheitern. Die Abbildung auf die Backend-Spalten
/// `schlaf_von` / `schlaf_bis` ("HH:mm") ist verlustfrei und in beide Richtungen total
/// (`PizzaConfig.hhmm(_:)` / `PizzaConfig.minuten(fromHHmm:)`), weil beide Darstellungen
/// exakt dieselben 1440 Minutenwerte eines Tages beschreiben - Sekunden gibt es in keiner von beiden.
struct PizzaConfig: Codable, Equatable {
    var mehltyp: Mehltyp = .tipo00
    var hefetyp: Hefetyp = .frisch
    var knetmethode: Knetmethode = .maschine
    var anzahlPizzen: Int = 6
    var teiglingsgewichtG: Double = 275
    var raumtempC: Double = 22
    /// nil = Mehl hat Raumtemperatur (der Normalfall).
    var mehltempOverride: Double? = nil
    /// nil = Hydration des Mehltyps.
    var hydrationOverride: Double? = nil
    /// Kalibrierkonstante des Gaermodells, im Advanced-Bereich einstellbar.
    var kFaktor: Double = PizzaKonstanten.kDefault
    /// Nachtruhe-Beginn, Minuten seit Mitternacht.
    var schlafVon: Int = PizzaKonstanten.schlafVonDefault
    /// Nachtruhe-Ende, Minuten seit Mitternacht.
    var schlafBis: Int = PizzaKonstanten.schlafBisDefault
    /// Kuehlschranktemperatur fuer die kalte Gare (Advanced 2-10 C).
    var fridgeTempC: Double = PizzaKonstanten.fridgeTempDefault

    static let standard = PizzaConfig()

    init() {}

    // Toleranter Decoder: fehlende Schluessel (z. B. `fridgeTempC` in aelteren gespeicherten
    // Configs) fallen auf den Default zurueck, statt das Decodieren scheitern zu lassen. Der
    // Encoder bleibt synthetisiert - die Schluesselnamen sind die Property-Namen.
    private enum CodingKeys: String, CodingKey {
        case mehltyp, hefetyp, knetmethode, anzahlPizzen, teiglingsgewichtG, raumtempC
        case mehltempOverride, hydrationOverride, kFaktor, schlafVon, schlafBis, fridgeTempC
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mehltyp = (try? c.decode(Mehltyp.self, forKey: .mehltyp)) ?? .tipo00
        hefetyp = (try? c.decode(Hefetyp.self, forKey: .hefetyp)) ?? .frisch
        knetmethode = (try? c.decode(Knetmethode.self, forKey: .knetmethode)) ?? .maschine
        anzahlPizzen = (try? c.decode(Int.self, forKey: .anzahlPizzen)) ?? 6
        teiglingsgewichtG = (try? c.decode(Double.self, forKey: .teiglingsgewichtG)) ?? 275
        raumtempC = (try? c.decode(Double.self, forKey: .raumtempC)) ?? 22
        mehltempOverride = try? c.decode(Double.self, forKey: .mehltempOverride)
        hydrationOverride = try? c.decode(Double.self, forKey: .hydrationOverride)
        kFaktor = (try? c.decode(Double.self, forKey: .kFaktor)) ?? PizzaKonstanten.kDefault
        schlafVon = (try? c.decode(Int.self, forKey: .schlafVon)) ?? PizzaKonstanten.schlafVonDefault
        schlafBis = (try? c.decode(Int.self, forKey: .schlafBis)) ?? PizzaKonstanten.schlafBisDefault
        fridgeTempC = (try? c.decode(Double.self, forKey: .fridgeTempC)) ?? PizzaKonstanten.fridgeTempDefault
    }

    // MARK: Abgeleitete Werte

    /// Aufgeloeste Hydration; ein Override wird hier (und nicht erst im Rechenkern) begrenzt,
    /// damit jeder Aufrufer denselben Wert sieht.
    var hydration: Double {
        guard let o = hydrationOverride else { return mehltyp.hydrationDefault }
        return Swift.min(Swift.max(o, PizzaKonstanten.hydrationMin), PizzaKonstanten.hydrationMax)
    }

    var mehltempC: Double {
        let t = mehltempOverride ?? raumtempC
        return Swift.min(Swift.max(t, PizzaKonstanten.mehltempMin), PizzaKonstanten.mehltempMax)
    }

    var teigGesamtG: Double { Double(anzahlPizzen) * teiglingsgewichtG }

    /// schlafVon == schlafBis heisst: keine Nachtruhe, immer wach.
    var nachtruheAktiv: Bool { schlafVon != schlafBis }

    var schlafVonHHmm: String { PizzaConfig.hhmm(schlafVon) }
    var schlafBisHHmm: String { PizzaConfig.hhmm(schlafBis) }

    // MARK: Brueckenfunktionen zu den Backend-Spalten ("HH:mm")

    static func hhmm(_ minutenSeitMitternacht: Int) -> String {
        let m = normalisierteTagesminute(minutenSeitMitternacht)
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    static func minuten(fromHHmm s: String) -> Int? {
        let teile = s.split(separator: ":")
        guard teile.count == 2,
              let h = Int(teile[0]), let m = Int(teile[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    /// Holt jeden Int in [0, 1440) - auch negative (Swift-% kann negativ werden).
    static func normalisierteTagesminute(_ v: Int) -> Int {
        ((v % PizzaKonstanten.minutenProTag) + PizzaKonstanten.minutenProTag) % PizzaKonstanten.minutenProTag
    }

    /// Bringt strukturelle Werte in ihre gueltigen Bereiche, damit der Rechenkern nie Unsinn liefert.
    /// raumtempC wird bewusst NICHT begrenzt: die beiden Temperatur-Warnungen sind laut Modell
    /// nicht blockierend und muessen daher ausloesen koennen.
    func normalisiert() -> PizzaConfig {
        var c = self
        c.anzahlPizzen = Swift.min(Swift.max(anzahlPizzen, PizzaKonstanten.anzahlMin), PizzaKonstanten.anzahlMax)
        c.teiglingsgewichtG = Swift.min(Swift.max(teiglingsgewichtG, PizzaKonstanten.gewichtMin), PizzaKonstanten.gewichtMax)
        c.kFaktor = Swift.max(kFaktor, 0.1)
        c.fridgeTempC = Swift.min(Swift.max(fridgeTempC, PizzaKonstanten.fridgeTempMin), PizzaKonstanten.fridgeTempMax)
        c.schlafVon = PizzaConfig.normalisierteTagesminute(schlafVon)
        c.schlafBis = PizzaConfig.normalisierteTagesminute(schlafBis)
        return c
    }
}

// MARK: - Ergebnisbausteine

struct PizzaZutaten: Equatable {
    /// Bereits gerundet: Mehl/Wasser/Salz auf 1 g bzw. 1 ml, Hefe auf 0,1 g.
    let mehlG: Double
    let wasserMl: Double
    let salzG: Double
    /// Hefe des gewaehlten Hefetyps - das ist der Wert, der abgewogen wird.
    let hefeG: Double
    let hefeFrischG: Double
    let hefeTrockenG: Double
    /// Frischhefe in Prozent vom Mehl, bereits auf [0,05 … 0,8] begrenzt.
    let hefePct: Double
    let wasserTempC: Double
    let wasserTempGeclampt: Bool
    let semolaG: Double
}

/// Art eines Planschritts. Traegt Titel/Icon und - wichtig fuer den Solver - die Unterscheidung
/// Handgriff vs. passiver Gaerblock.
enum PizzaSchrittArt: String, Codable, CaseIterable {
    case kneten
    case entspannen
    case stockgare
    case dehnenFalten1
    case dehnenFalten2
    case portionieren
    case stueckgare
    /// Passive kalte Kuehlschrankgare - spannt die Nacht und braucht keinen Handgriff.
    case kuehlschrank
    /// Anwaermen + Stueckgare nach dem Kuehlschrank. Der Zeitpunkt (= Kugeln rausnehmen)
    /// ist ein Handgriff, deshalb `istAktion == true`.
    case anwaermen
    case ofenAn
    case backen
    case essen

    /// Handgriffe muessen in der Wachzeit liegen; Stock-, Stueck- und Kuehlschrankgare laufen
    /// von allein und duerfen die Nacht ueberspannen.
    var istAktion: Bool {
        switch self {
        case .stockgare, .stueckgare, .kuehlschrank: return false
        default: return true
        }
    }

    var titel: String {
        switch self {
        case .kneten: return "Kneten"
        case .entspannen: return "Entspannen & Rundwirken"
        case .stockgare: return "Stockgare"
        case .dehnenFalten1: return "Dehnen & Falten (1/2)"
        case .dehnenFalten2: return "Dehnen & Falten (2/2)"
        case .portionieren: return "Portionieren"
        case .stueckgare: return "Stückgare"
        case .kuehlschrank: return "Kühlschrank"
        case .anwaermen: return "Anwärmen & Stückgare"
        case .ofenAn: return "Ofen an"
        case .backen: return "Backen"
        case .essen: return "Essen"
        }
    }

    var icon: String {
        switch self {
        case .kneten: return "hands.sparkles.fill"
        case .entspannen: return "circle.dashed"
        case .stockgare: return "clock.arrow.circlepath"
        case .dehnenFalten1, .dehnenFalten2: return "arrow.up.and.down.and.arrow.left.and.right"
        case .portionieren: return "square.grid.2x2"
        case .stueckgare: return "clock"
        case .kuehlschrank: return "refrigerator"
        case .anwaermen: return "thermometer.sun"
        case .ofenAn: return "flame"
        case .backen: return "flame.fill"
        case .essen: return "fork.knife"
        }
    }
}

struct PizzaSchritt: Identifiable, Equatable, Hashable {
    let art: PizzaSchrittArt
    let zeit: Date
    let detail: String?

    var titel: String { art.titel }
    var icon: String { art.icon }
    var istAktion: Bool { art.istAktion }
    /// Stabil und ohne UUID, damit derselbe Plan zweimal berechnet dieselben IDs hat
    /// (sonst animiert SwiftUI bei jedem Neuberechnen die ganze Liste neu).
    var id: String { "\(art.rawValue)@\(Int(zeit.timeIntervalSince1970))" }
}

/// Nicht blockierende Hinweise zu einem fertigen Plan.
/// Warum weicht ein Plan vom 6-Stunden-Standard ab? Der Hinweistext darf keine Ursache
/// behaupten, die gar nicht zutrifft - bei abgeschalteter Nachtruhe kann es nur die Hefe sein.
enum PizzaVerschiebeGrund: Equatable, Hashable {
    /// Beim Standardplan fiele ein Handgriff in den Schlaf.
    case nachtruhe
    /// Der Standardplan braeuchte mehr Hefe als die Geschmacksgrenze erlaubt (meist: zu kalt).
    case hefe
    case beides
}

enum PizzaHinweis: Identifiable, Equatable, Hashable {
    case wasserTempGeclampt(Double)
    case raumtempNiedrig(Double)
    case raumtempHoch(Double)
    case sehrLangeGare(Double)
    case planVerschoben(nettoMinuten: Int, grund: PizzaVerschiebeGrund)
    /// Warm: wacher Plan gefunden, aber das Fenster ist knapp - etwas mehr Hefe als ideal.
    case knappesFensterMehrHefe
    /// Kalt: die Anwaermzeit nach dem Kuehlschrank musste unter das Ideal gekuerzt werden.
    case kurzeAnwaermzeit
    /// Kalt: sehr lange Kuehlschrankgare -> rechnerisch sehr wenig Hefe (roher Prozentwert).
    case sehrWenigHefe(Double)
    /// Notfall (Essen mitten in der Nacht): so viele Handgriffe lassen sich nicht wach legen.
    case nachtHandgriffeUnvermeidbar(Int)
    /// Die gesamte Gaerzeit passt nicht zur Gaer-Toleranz des gewaehlten Mehls - rein
    /// informativ, mit einer konkreten Mehl-Empfehlung (im Calculator formuliert).
    case mehlGaertoleranz(empfehlung: String)

    var text: String {
        switch self {
        case .wasserTempGeclampt(let t):
            return "Die rechnerische Wassertemperatur liegt außerhalb von 5–35 °C und wurde auf "
                + "\(PizzaCalculator.grad(t)) °C begrenzt. Die Zielteigtemperatur von 24 °C wird so nicht exakt erreicht."
        case .raumtempNiedrig(let t):
            return "Bei \(PizzaCalculator.grad(t)) °C ist eine Raumtemperatur-Gare unter 8 Stunden kaum praktikabel."
        case .raumtempHoch(let t):
            return "Bei \(PizzaCalculator.grad(t)) °C leiden Geschmack und Teigstruktur."
        case .sehrLangeGare(let p):
            return "Sehr lange Gare – rechnerisch reichen \(PizzaCalculator.prozent(p)) % Hefe. "
                + "Für dieses Zeitfenster wäre eine Kühlschrankgare besser geeignet."
        case .planVerschoben(let netto, let grund):
            let dauern = "\(PizzaCalculator.dauer(netto)) Gare statt \(PizzaCalculator.dauer(PizzaKonstanten.nettoStandard))."
            switch grund {
            case .nachtruhe:
                return "Wegen der Nachtruhe weicht der Plan vom 6-Stunden-Standard ab: " + dauern
            case .hefe:
                return "Für den 6-Stunden-Standard wäre bei dieser Raumtemperatur zu viel Hefe nötig – "
                    + "der Plan gärt deshalb länger: " + dauern
            case .beides:
                return "Nachtruhe und Raumtemperatur lassen den 6-Stunden-Standard nicht zu: " + dauern
            }
        case .knappesFensterMehrHefe:
            return "Knappes Zeitfenster – der Teig bekommt etwas mehr Hefe als ideal, damit er "
                + "bis zur Essenszeit sicher fertig ist."
        case .kurzeAnwaermzeit:
            return "Kurze Anwärmzeit – die Teiglinge sind beim Backen evtl. noch etwas kühl. "
                + "Wenn möglich, sie früher aus dem Kühlschrank nehmen."
        case .sehrWenigHefe(let p):
            return "Sehr lange Kühlschrankgare – rechnerisch reichen \(PizzaCalculator.prozent(p)) % "
                + "Frischhefe. Bei so wenig Hefe die Menge lieber knapp abwiegen."
        case .nachtHandgriffeUnvermeidbar(let n):
            let handgriffe = n == 1 ? "1 Handgriff" : "\(PizzaCalculator.ganzzahl(n)) Handgriffe"
            return "Für diese Uhrzeit lassen sich \(handgriffe) in der Nacht nicht vermeiden – "
                + "dafür muss der Wecker klingeln."
        case .mehlGaertoleranz(let empfehlung):
            return empfehlung
        }
    }

    /// Nur die begrenzte Wassertemperatur ist ein echter Mangel - der Plan kann die
    /// Zielteigtemperatur dann nicht mehr treffen. Alles andere ist Geschmacksberatung.
    var istFehler: Bool {
        switch self {
        case .wasserTempGeclampt: return true
        default: return false
        }
    }

    var id: String { text }
}

/// Ein vollstaendig geloester Plan - warm (Same-Day) ODER kalt (Kuehlschrankgare).
///
/// Fuer beide Varianten sind `stockMinuten`/`stueckMinuten`/`fridgeMinuten` so belegt, dass
/// `gesamtdauerMinuten` und die UI dieselbe Formel benutzen koennen:
/// - warm: stock+stueck = netto, fridge = 0.
/// - kalt: stock = warme Stockgare (bulk), stueck = Anwaermen/Appretto, fridge = Kuehlschrankgare.
struct PizzaPlan: Equatable {
    let config: PizzaConfig
    let variante: PizzaVariante
    let zutaten: PizzaZutaten
    let schritte: [PizzaSchritt]
    /// warm: die Netto-Gare (Raumtemperatur). kalt: die gesamte Gaerzeit bulk+kuehlschrank+appretto.
    let nettoMinuten: Int
    /// warm: Stockgare. kalt: warme Stockgare (bulk) vor dem Kuehlschrank.
    let stockMinuten: Int
    /// warm: Stueckgare. kalt: Anwaermen + Stueckgare (appretto) nach dem Kuehlschrank.
    let stueckMinuten: Int
    /// Passive Kuehlschrankgare in Minuten - 0 bei der warmen Variante.
    let fridgeMinuten: Int
    /// Erster Handgriff (Kneten).
    let startzeit: Date
    let essenszeit: Date
    let hinweise: [PizzaHinweis]

    /// Nur die warme Variante hat einen 6-h-Standard, von dem sie abweichen kann.
    var weichtVomStandardAb: Bool { variante == .warm && nettoMinuten != PizzaKonstanten.nettoStandard }

    /// Erster Handgriff bis Essen. Fuer beide Varianten gilt: die vier Fixbloecke plus die drei
    /// Gaerabschnitte (bei warm ist fridge = 0 und stock+stueck = netto).
    var gesamtdauerMinuten: Int {
        PizzaKonstanten.fixSumme + stockMinuten + stueckMinuten + fridgeMinuten
    }
}

/// Das Ergebnis des Solvers: die Essenszeit ist fix, deshalb gibt es NIE ein "geht nicht".
///
/// Im Normalfall ist mindestens eine der beiden Varianten gesetzt (oft beide - dann waehlt der
/// Nutzer in der UI). `fruehestesMoeglichesEssen` ist ausschliesslich dann gesetzt, wenn beide
/// nil sind - der einzige physische Grenzfall: weniger als 4,5 h Vorlauf ab jetzt. Dann zeigt die
/// UI einen sanften Hinweis "frühestens HH:MM", KEINE Absage.
struct PizzaPlanung: Equatable {
    var warm: PizzaPlan?
    var kalt: PizzaPlan?
    var fruehestesMoeglichesEssen: Date?

    /// Bequemer Zugriff: irgendein vorhandener Plan (warm bevorzugt), fuer Vorschau/Kurzstatus.
    var irgendeiner: PizzaPlan? { warm ?? kalt }
    /// Es gibt mindestens einen Plan.
    var hatPlan: Bool { warm != nil || kalt != nil }
}

// MARK: - Navigation

enum PizzaTab: Hashable { case planer, rezepte }

// MARK: - Backend-Modelle (generisches v1-CRUD: pizza-rezepte / pizza-notizen)

/// Eine gespeicherte Rezeptur = eine vollstaendige `PizzaConfig` plus Verwaltungsdaten.
///
/// Die Config ist ein eigenes Feld (statt 11 flach ausgerollter Spalten): der Planer arbeitet
/// ausschliesslich mit `PizzaConfig`, also ist `rezept.config` das einzige, was ein Aufrufer
/// braucht - und `PizzaRezept(from:name:)` + `.body` der einzige Weg zurueck zum Backend.
/// Die Runde Config -> body -> fields -> config ist verlustfrei; einzige Ausnahme ist das
/// Teiglingsgewicht, das die Spalte `teiglingsgewicht` als INTEGER fuehrt (ganze Gramm - der
/// Planer stellt es ohnehin nur in ganzen Gramm ein).
struct PizzaRezept: Identifiable, Hashable {
    let id: Int
    var name: String
    var config: PizzaConfig
    var favorit: Bool
    var notiz: String?
    let createdAt: String?
    let updatedAt: String?

    /// Neue, noch nicht gespeicherte Rezeptur (id 0 - die vergibt das Backend beim POST).
    init(from config: PizzaConfig, name: String, favorit: Bool = false, notiz: String? = nil) {
        id = 0
        self.name = name
        self.config = config.normalisiert()
        self.favorit = favorit
        self.notiz = notiz
        createdAt = nil
        updatedAt = nil
    }

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        name = Coerce.str(f["name"]) ?? "Rezeptur"
        favorit = Coerce.bool(f["favorit"])
        notiz = Coerce.str(f["notiz"])
        createdAt = Coerce.str(f["created_at"])
        updatedAt = Coerce.str(f["updated_at"])

        // Unbekannte/fehlende Werte fallen auf die Defaults zurueck, damit eine aeltere oder
        // per API angelegte Zeile den Planer nie in einen ungueltigen Zustand bringt.
        var c = PizzaConfig()
        c.mehltyp = Coerce.str(f["mehltyp"]).flatMap(Mehltyp.init(rawValue:)) ?? c.mehltyp
        c.hefetyp = Coerce.str(f["hefetyp"]).flatMap(Hefetyp.init(rawValue:)) ?? c.hefetyp
        c.knetmethode = Coerce.str(f["knetmethode"]).flatMap(Knetmethode.init(rawValue:)) ?? c.knetmethode
        c.anzahlPizzen = Coerce.int(f["anzahl_pizzen"]) ?? c.anzahlPizzen
        c.teiglingsgewichtG = Coerce.double(f["teiglingsgewicht"]) ?? c.teiglingsgewichtG
        c.raumtempC = Coerce.double(f["raumtemp"]) ?? c.raumtempC
        // NULL bedeutet hier ausdruecklich "Default ableiten" - also nil lassen, nicht fuellen.
        c.mehltempOverride = Coerce.double(f["mehltemp"])
        c.hydrationOverride = Coerce.double(f["hydration"])
        c.kFaktor = Coerce.double(f["k_faktor"]) ?? c.kFaktor
        c.schlafVon = Coerce.str(f["schlaf_von"]).flatMap(PizzaConfig.minuten(fromHHmm:)) ?? c.schlafVon
        c.schlafBis = Coerce.str(f["schlaf_bis"]).flatMap(PizzaConfig.minuten(fromHHmm:)) ?? c.schlafBis
        c.fridgeTempC = Coerce.double(f["fridge_temp"]) ?? c.fridgeTempC
        config = c.normalisiert()
    }

    /// Feldwerte fuer POST/PATCH (Spaltennamen des Backends). NULL-faehige Spalten werden
    /// bewusst als NSNull gesendet, damit ein entfernter Override auch wirklich geloescht wird.
    var body: [String: Any] {
        let c = config.normalisiert()
        var b: [String: Any] = [
            "name": name,
            "anzahl_pizzen": c.anzahlPizzen,
            "teiglingsgewicht": Int(c.teiglingsgewichtG.rounded()),
            "mehltyp": c.mehltyp.rawValue,
            "hefetyp": c.hefetyp.rawValue,
            "raumtemp": c.raumtempC,
            "knetmethode": c.knetmethode.rawValue,
            "k_faktor": c.kFaktor,
            "schlaf_von": c.schlafVonHHmm,
            "schlaf_bis": c.schlafBisHHmm,
            "fridge_temp": c.fridgeTempC,
            "favorit": favorit ? 1 : 0,
        ]
        b["mehltemp"] = c.mehltempOverride.map { $0 as Any } ?? NSNull()
        b["hydration"] = c.hydrationOverride.map { $0 as Any } ?? NSNull()
        b["notiz"] = notiz.map { $0 as Any } ?? NSNull()
        return b
    }

    // PizzaConfig ist Equatable, aber nicht Hashable - Identitaet ist ohnehin die id.
    static func == (a: PizzaRezept, b: PizzaRezept) -> Bool { a.id == b.id && a.config == b.config }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Verkostungs-/Variations-Notiz zu einer Rezeptur.
struct PizzaNotiz: Identifiable, Hashable {
    let id: Int
    let rezeptId: Int
    var text: String
    /// 1-5 Sterne, optional.
    var bewertung: Int?
    /// Datum im Format "YYYY-MM-DD".
    var gebackenAm: String?
    let createdAt: String?

    init(fields f: [String: Any]) {
        id = Coerce.int(f["id"]) ?? 0
        rezeptId = Coerce.int(f["rezept_id"]) ?? 0
        text = Coerce.str(f["text"]) ?? ""
        bewertung = Coerce.int(f["bewertung"])
        gebackenAm = Coerce.str(f["gebacken_am"])
        createdAt = Coerce.str(f["created_at"])
    }
}

// MARK: - Textbausteine fuer die Backend-Datumsspalten

/// Datumsformate der Backend-Spalten. Bewusst getrennt von `PizzaCalculator`: dort geht es um
/// Zeitpunkte eines Plans, hier um die Zeitstempel gespeicherter Zeilen.
enum PizzaText {
    /// SQLite-Zeitstempel ("2026-07-17 12:15:55") oder Datum ("2026-07-17") -> "17.07.2026".
    /// Leere/unbekannte Werte ergeben einen leeren String (die View blendet sie dann aus).
    static func datum(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        let tag = String(raw.prefix(10))
        let teile = tag.split(separator: "-")
        guard teile.count == 3 else { return tag }
        return "\(teile[2]).\(teile[1]).\(teile[0])"
    }

    /// Date -> "YYYY-MM-DD" (Konvention der Spalte `gebacken_am`).
    static func isoDatum(_ d: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
