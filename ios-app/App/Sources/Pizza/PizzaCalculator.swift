import Foundation

/// Rechenkern des Pizza-Planers: ausschliesslich statische, reine Funktionen.
///
/// "jetzt" und der Calendar werden immer hereingereicht - kein `Date()` und kein `.current`
/// im Inneren. Nur so laesst sich der Solver mit fester Zeitzone deterministisch testen.
enum PizzaCalculator {

    // MARK: - Gaermodell

    /// Verdopplung der Gaeraktivitaet je 7 K - der Anker des ganzen Modells.
    static func gaerFaktor(_ t: Double) -> Double {
        pow(2, (t - 20) / 7)
    }

    /// Frischhefe in Prozent vom Mehl - UNGECLAMPT.
    /// Der Solver braucht den rohen Wert, weil er gerade an der Obergrenze entscheidet;
    /// erst `zutaten(config:nettoMinuten:)` begrenzt fuer die Anzeige.
    static func hefeFrischPct(nettoStunden: Double, raumtemp: Double, mehltyp: Mehltyp, k: Double) -> Double {
        let nenner = nettoStunden * gaerFaktor(raumtemp) * mehltyp.mehlFaktor
        // Unsinnige Eingaben (Zeit 0, absurd kalt) sollen als "geht nicht" durchfallen,
        // nicht als inf/NaN weiterlaufen.
        guard nenner > 0, nenner.isFinite else { return PizzaKonstanten.hefePctMax + 1 }
        return k / nenner
    }

    // MARK: - Zutaten

    static func zutaten(config: PizzaConfig, nettoMinuten: Int) -> PizzaZutaten {
        let c = config.normalisiert()
        let netto = begrenztesNetto(nettoMinuten)
        let pctRoh = hefeFrischPct(nettoStunden: Double(netto) / 60,
                                   raumtemp: c.raumtempC, mehltyp: c.mehltyp, k: c.kFaktor)
        let pct = min(max(pctRoh, PizzaKonstanten.hefePctMin), PizzaKonstanten.hefePctMax)

        let mehlRoh = mehlGrammRoh(config: c, hefeFrischPct: pct)
        let frischRoh = mehlRoh * pct / 100
        let trockenRoh = frischRoh / 3
        let wt = wasserTemp(config: c)

        // Gerundet wird erst ganz am Ende und jeweils aus dem ungerundeten Mehlgewicht,
        // damit sich Rundungsfehler nicht fortpflanzen.
        return PizzaZutaten(
            mehlG: mehlRoh.rounded(),
            wasserMl: (mehlRoh * c.hydration).rounded(),
            salzG: (mehlRoh * PizzaKonstanten.salzAnteil).rounded(),
            hefeG: zehntel(c.hefetyp == .trocken ? trockenRoh : frischRoh),
            hefeFrischG: zehntel(frischRoh),
            hefeTrockenG: zehntel(trockenRoh),
            hefePct: pct,
            wasserTempC: wt.temp,
            wasserTempGeclampt: wt.geclampt,
            semolaG: Double(c.anzahlPizzen) * PizzaKonstanten.semolaProTeiglingG
        )
    }

    /// Mehlgewicht (ungerundet) zu einem gegebenen Frischhefe-Prozentsatz.
    /// Zur Teigmasse zaehlt nur die TATSAECHLICH zugegebene Hefe - bei Trockenhefe also ein Drittel.
    private static func mehlGrammRoh(config: PizzaConfig, hefeFrischPct pct: Double) -> Double {
        let hefeAnteil = (config.hefetyp == .trocken ? pct / 3 : pct) / 100
        return config.teigGesamtG / (1 + config.hydration + PizzaKonstanten.salzAnteil + hefeAnteil)
    }

    static func wasserTemp(config: PizzaConfig) -> (temp: Double, geclampt: Bool) {
        let c = config.normalisiert()
        let roh = 3 * PizzaKonstanten.zielTeigtempC - c.raumtempC - c.mehltempC - c.knetmethode.reibung
        let geclampt = roh < PizzaKonstanten.wasserTempMin || roh > PizzaKonstanten.wasserTempMax
        return (min(max(roh, PizzaKonstanten.wasserTempMin), PizzaKonstanten.wasserTempMax), geclampt)
    }

    // MARK: - Nachtruhe

    /// Prueft die TAGESZEIT gegen das wiederkehrende Nachtruhe-Fenster.
    static func istSchlafend(_ date: Date, config: PizzaConfig, calendar: Calendar = .current) -> Bool {
        let c = config.normalisiert()
        guard c.nachtruheAktiv else { return false }
        return istSchlafend(tagesminute: tagesminute(date, calendar: calendar), config: c)
    }

    /// Dasselbe auf der blossen Tagesminute - ohne Calendar. Der Solver prueft bis zu sieben
    /// Zeitpunkte je Kandidat und darf dafuer nicht zwei Calendar-Roundtrips je Punkt zahlen.
    /// Erwartet eine normalisierte Config und eine Minute in [0, 1440).
    private static func istSchlafend(tagesminute t: Int, config c: PizzaConfig) -> Bool {
        guard c.nachtruheAktiv else { return false }
        if c.schlafVon < c.schlafBis { return t >= c.schlafVon && t < c.schlafBis }
        // Der Normalfall (23:00 -> 07:00) ueberspannt Mitternacht.
        return t >= c.schlafVon || t < c.schlafBis
    }

    private static func tagesminute(_ d: Date, calendar: Calendar) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: d)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    /// Liegt im gesamten Planfenster vor `essen` eine Zeitumstellung?
    ///
    /// Nur dann duerfen die Schrittzeiten nicht per Int-Arithmetik auf der Tagesminute
    /// hergeleitet werden: `plus` addiert ABSOLUTE Minuten, die Wanduhr springt an diesen
    /// zwei Tagen im Jahr aber um eine Stunde - beide Rechnungen laufen dann auseinander.
    /// An allen anderen Tagen sind sie exakt gleichwertig, und der Solver spart sich pro
    /// Kandidat sieben Calendar-Roundtrips. Ein Aufruf je `loese` statt Hunderter.
    private static func zeitumstellungImFenster(essen: Date, calendar: Calendar) -> Bool {
        let fensterMinuten = PizzaKonstanten.fixSumme + PizzaKonstanten.nettoMax
        let fensterStart = essen.addingTimeInterval(-Double(fensterMinuten) * 60)
        guard let naechste = calendar.timeZone.nextDaylightSavingTimeTransition(after: fensterStart) else { return false }
        return naechste <= essen
    }

    /// Liegen ALLE Handgriffe eines Kandidaten in der Wachzeit? (Stock- und Stueckgare sind
    /// passiv und duerfen die Nacht ueberspannen.) Gemeinsame Wahrheit von Solver und Begruendung.
    private static func alleHandgriffeWach(config c: PizzaConfig, essen: Date, netto: Int,
                                           essenMinute: Int, exakt: Bool, calendar: Calendar) -> Bool {
        // Ohne Nachtruhe kann kein Handgriff schlafen - der teure Teil entfaellt komplett.
        guard c.nachtruheAktiv else { return true }
        return rohplan(config: c, netto: netto)
            .filter { $0.art.istAktion }
            .allSatisfy { zeile in
                if exakt {
                    return !istSchlafend(plus(zeile.offset, essen, calendar), config: c, calendar: calendar)
                }
                let m = PizzaConfig.normalisierteTagesminute(essenMinute + zeile.offset)
                return !istSchlafend(tagesminute: m, config: c)
            }
    }

    // MARK: - Zeitplan

    static func stockMinuten(_ netto: Int) -> Int {
        Int((Double(netto) * PizzaKonstanten.stockAnteil).rounded())
    }

    /// Rohplan: Offset in Minuten relativ zur Essenszeit (negativ = davor), chronologisch.
    /// EINZIGE Quelle der Zeitplan-Wahrheit - `schritte` haengt nur noch Texte daran und der
    /// Solver liest hier die Handgriffe ab. So koennen die beiden nicht auseinanderlaufen.
    private static func rohplan(config: PizzaConfig, netto: Int) -> [(offset: Int, art: PizzaSchrittArt)] {
        let stock = stockMinuten(netto)
        let start = -(PizzaKonstanten.fixSumme + netto)
        let stockgare = start + PizzaKonstanten.fixKneten + PizzaKonstanten.fixEntspannen
        let portionieren = stockgare + stock

        var p: [(offset: Int, art: PizzaSchrittArt)] = [
            (offset: start, art: .kneten),
            (offset: start + PizzaKonstanten.fixKneten, art: .entspannen),
            (offset: stockgare, art: .stockgare),
        ]
        if config.mehltyp == .dinkel {
            p.append((offset: stockgare + 30, art: .dehnenFalten1))
            p.append((offset: stockgare + 60, art: .dehnenFalten2))
        }
        p.append((offset: portionieren, art: .portionieren))
        p.append((offset: portionieren + PizzaKonstanten.fixPortionieren, art: .stueckgare))
        p.append((offset: -(PizzaKonstanten.fixBacken + PizzaKonstanten.vorheizMin), art: .ofenAn))
        p.append((offset: -PizzaKonstanten.fixBacken, art: .backen))
        p.append((offset: 0, art: .essen))
        return p
    }

    static func schritte(config: PizzaConfig, essen: Date, nettoMinuten: Int, calendar: Calendar = .current) -> [PizzaSchritt] {
        let c = config.normalisiert()
        let netto = begrenztesNetto(nettoMinuten)
        let stock = stockMinuten(netto)
        let stueck = netto - stock
        let wt = wasserTemp(config: c)

        return rohplan(config: c, netto: netto).map { zeile in
            PizzaSchritt(art: zeile.art,
                         zeit: plus(zeile.offset, essen, calendar),
                         detail: detail(fuer: zeile.art, config: c, stock: stock, stueck: stueck, wasserTemp: wt.temp))
        }
    }

    private static func detail(fuer art: PizzaSchrittArt, config c: PizzaConfig,
                               stock: Int, stueck: Int, wasserTemp: Double) -> String? {
        switch art {
        case .kneten:
            // Reihenfolge = Reihenfolge der Handgriffe: Hefe ins Wasser, kneten, Salz spaeter.
            var t = c.hefetyp.aufloesHinweis
            t += " \(c.mehltyp.knetzeitText(c.knetmethode)), Wasser \(grad(wasserTemp)) °C."
            // Spec §3.2: Salz nicht mit der Hefe zusammen einwerfen, sonst bremst es sie unnoetig.
            t += " Salz erst zugeben, wenn rund 70 % des Mehls eingearbeitet sind."
            if let h = c.mehltyp.knetHinweis { t += " " + h }
            return t
        case .entspannen:
            return "15 Min. abgedeckt entspannen, dann rundwirken."
        case .stockgare:
            return "\(dauer(stock)) abgedeckt bei \(grad(c.raumtempC)) °C."
        case .dehnenFalten1, .dehnenFalten2:
            return "Teig einmal rundum dehnen und falten."
        case .portionieren:
            // Int-Interpolation ist hier gefahrlos: das Ergebnis ist ein String, der als Variable
            // in Text() landet - kein LocalizedStringKey, also kein Tausenderpunkt.
            return "In \(c.anzahlPizzen) Teiglinge à \(gramm(c.teiglingsgewichtG)) g teilen "
                + "und straff rundschleifen."
        case .stueckgare:
            return "\(dauer(stueck)) abgedeckt bei \(grad(c.raumtempC)) °C – Ballenbox."
        case .ofenAn:
            return "Gozney Dome anzünden – \(dauer(PizzaKonstanten.vorheizMin)) auf Maximum vorheizen."
        case .backen:
            return "Ausbreiten, belegen, backen – je Pizza 60–90 s bei 430–480 °C, "
                + "rund \(dauer(PizzaKonstanten.fixBacken)) für alle."
        case .essen:
            return nil
        }
    }

    // MARK: - Solver

    /// Kandidatenraster aufsteigend: 5-Minuten-Schritte plus exakt der Standardwert.
    static func nettoKandidaten() -> [Int] {
        var werte = Set<Int>()
        var n = PizzaKonstanten.nettoMin
        while n <= PizzaKonstanten.nettoMax {
            werte.insert(n)
            n += 5
        }
        werte.insert(PizzaKonstanten.nettoStandard)
        return werte.sorted()
    }

    /// Dieselben Kandidaten in Wunschreihenfolge: naeher am 6-h-Standard zuerst, bei Gleichstand
    /// das laengere netto (laengere Gare = mehr Aroma). Damit kann der Solver beim ersten
    /// Treffer abbrechen - im Normalfall gewinnt der Standardplan in der ersten Runde.
    ///
    /// Einmal berechnet, nicht je Aufruf: die Suche nach der fruehestmoeglichen Essenszeit ruft
    /// `loese` bis zu 577 mal auf, und die Liste haengt von keiner Eingabe ab.
    private static let kandidatenPrio: [Int] = nettoKandidaten().sorted { a, b in
        let da = abs(a - PizzaKonstanten.nettoStandard)
        let db = abs(b - PizzaKonstanten.nettoStandard)
        if da != db { return da < db }
        return a > b
    }

    /// Ergebnis des inneren Loesers.
    private struct Loesung {
        /// Bester gueltiger Kandidat.
        var gewaehlt: Int?
        /// Bester Kandidat, dessen Handgriffe alle in der Wachzeit liegen - auch wenn er an der
        /// Hefe scheitert. Unterscheidet Fall (a) von Fall (b).
        var besterWach: Int?
    }

    /// Der eigentliche Kandidatenscan - bewusst getrennt von `plan`, damit die Suche nach der
    /// fruehestmoeglichen Essenszeit sich nicht rekursiv selbst aufruft.
    /// Erwartet eine bereits normalisierte Config.
    private static func loese(config c: PizzaConfig, essen: Date, calendar: Calendar) -> Loesung {
        var l = Loesung()
        // Beides einmal je Scan statt einmal je Kandidat.
        let exakt = zeitumstellungImFenster(essen: essen, calendar: calendar)
        let essenMinute = tagesminute(essen, calendar: calendar)

        for netto in kandidatenPrio {
            // Der erste wache Kandidat kommt in dieser Reihenfolge nie NACH dem ersten gueltigen,
            // also ist hier bereits alles gefunden.
            if l.gewaehlt != nil { break }

            let stock = stockMinuten(netto)
            guard stock >= PizzaKonstanten.stockMin,
                  netto - stock >= PizzaKonstanten.stueckMin else { continue }

            let alleWach = alleHandgriffeWach(config: c, essen: essen, netto: netto,
                                              essenMinute: essenMinute, exakt: exakt, calendar: calendar)
            guard alleWach else { continue }
            if l.besterWach == nil { l.besterWach = netto }

            let pct = hefeFrischPct(nettoStunden: Double(netto) / 60,
                                    raumtemp: c.raumtempC, mehltyp: c.mehltyp, k: c.kFaktor)
            // Nur die OBERGRENZE schliesst aus: zu viel Hefe ruiniert den Geschmack.
            // Die Untergrenze bedeutet lediglich "sehr lange Gare" und wird als Hinweis gefuehrt -
            // wuerde sie ausschliessen, verloere man die aromatischsten Plaene.
            if pct <= PizzaKonstanten.hefePctMax { l.gewaehlt = netto }
        }
        return l
    }

    static func plan(config: PizzaConfig, essen: Date, jetzt: Date, calendar: Calendar = .current) -> PizzaErgebnis {
        let c = config.normalisiert()
        let frueheste = plus(PizzaKonstanten.minVorlaufMin, jetzt, calendar)
        // Ein Vorschlag vor jetzt+4,5 h waere wertlos, deshalb ist das in beiden Fehlerfaellen
        // die Untergrenze der Vorwaertssuche.
        let ab = max(essen, frueheste)

        if essen < frueheste {
            return .fehler(problemZuFrueh(config: c, ab: ab, calendar: calendar))
        }

        let l = loese(config: c, essen: essen, calendar: calendar)
        guard let netto = l.gewaehlt else {
            if let wach = l.besterWach {
                return .fehler(problemHefe(config: c, essen: essen, netto: wach, calendar: calendar))
            }
            return .fehler(problemNachtruhe(config: c, ab: ab, calendar: calendar))
        }
        return .plan(baue(config: c, essen: essen, netto: netto, calendar: calendar))
    }

    private static func baue(config c: PizzaConfig, essen: Date, netto: Int, calendar: Calendar) -> PizzaPlan {
        let z = zutaten(config: c, nettoMinuten: netto)
        let s = schritte(config: c, essen: essen, nettoMinuten: netto, calendar: calendar)
        let stock = stockMinuten(netto)

        var hinweise: [PizzaHinweis] = []
        if z.wasserTempGeclampt { hinweise.append(.wasserTempGeclampt(z.wasserTempC)) }
        if c.raumtempC < 18 { hinweise.append(.raumtempNiedrig(c.raumtempC)) }
        if c.raumtempC > 28 { hinweise.append(.raumtempHoch(c.raumtempC)) }
        let pctRoh = hefeFrischPct(nettoStunden: Double(netto) / 60,
                                   raumtemp: c.raumtempC, mehltyp: c.mehltyp, k: c.kFaktor)
        if pctRoh < PizzaKonstanten.hefePctMin { hinweise.append(.sehrLangeGare(pctRoh)) }
        if netto != PizzaKonstanten.nettoStandard {
            hinweise.append(.planVerschoben(nettoMinuten: netto,
                                            grund: verschiebeGrund(config: c, essen: essen, calendar: calendar)))
        }

        return PizzaPlan(config: c,
                         zutaten: z,
                         schritte: s,
                         nettoMinuten: netto,
                         stockMinuten: stock,
                         stueckMinuten: netto - stock,
                         startzeit: plus(-(PizzaKonstanten.fixSumme + netto), essen, calendar),
                         essenszeit: essen,
                         hinweise: hinweise)
    }

    /// Warum ist der 6-h-Standard nicht gewaehlt worden? Wird nur gefragt, wenn er es nicht wurde,
    /// also ist genau einer der beiden Gruende (oder beide) erfuellt - der Standard ist der erste
    /// Kandidat der Prioritaetsliste und haette sonst gewonnen.
    private static func verschiebeGrund(config c: PizzaConfig, essen: Date, calendar: Calendar) -> PizzaVerschiebeGrund {
        let n = PizzaKonstanten.nettoStandard
        let wach = alleHandgriffeWach(config: c, essen: essen, netto: n,
                                      essenMinute: tagesminute(essen, calendar: calendar),
                                      exakt: zeitumstellungImFenster(essen: essen, calendar: calendar),
                                      calendar: calendar)
        let pct = hefeFrischPct(nettoStunden: Double(n) / 60,
                                raumtemp: c.raumtempC, mehltyp: c.mehltyp, k: c.kFaktor)
        let hefeOk = pct <= PizzaKonstanten.hefePctMax
        switch (wach, hefeOk) {
        case (false, false): return .beides
        case (false, true): return .nachtruhe
        default: return .hefe
        }
    }

    // MARK: - Gegenvorschlaege

    /// Fruehestmoegliche Essenszeit ab `ab`, in 5-Minuten-Schritten, maximal +48 h.
    static func fruehesteEssenszeit(config: PizzaConfig, ab: Date, calendar: Calendar = .current) -> Date? {
        let c = config.normalisiert()
        let start = auf5MinutenAufrunden(ab, calendar: calendar)
        let maxSchritte = 48 * 60 / 5
        for i in 0...maxSchritte {
            let kandidat = plus(i * 5, start, calendar)
            if loese(config: c, essen: kandidat, calendar: calendar).gewaehlt != nil { return kandidat }
        }
        return nil
    }

    /// Kleinste Raumtemperatur (0,5-Schritte, hoechstens 28 °C), bei der ein gueltiger Plan existiert.
    /// Waermer heisst mehr Gaeraktivitaet heisst weniger Hefe - die Gueltigkeit waechst also
    /// monoton mit T. Deshalb ist der erste Treffer von unten auch das Minimum.
    static func kleinsteTauglicheRaumtemp(config: PizzaConfig, essen: Date, calendar: Calendar = .current) -> Double? {
        let c = config.normalisiert()
        var t = PizzaKonstanten.raumtempMin
        while t <= PizzaKonstanten.raumtempMax + 0.001 {
            var probe = c
            probe.raumtempC = t
            if loese(config: probe, essen: essen, calendar: calendar).gewaehlt != nil { return t }
            t += 0.5
        }
        return nil
    }

    /// Fall (a): es gaebe wache Plaene, aber alle brauchen mehr Hefe als die Geschmacksgrenze erlaubt.
    private static func problemHefe(config c: PizzaConfig, essen: Date, netto: Int, calendar: Calendar) -> PizzaProblem {
        // Bewusst der Kandidat, den der Solver GEWAEHLT haette - der Nutzer soll die Zahl zu
        // "seinem" Plan sehen. Die Menge wird aus dem UNGECLAMPTEN Prozentsatz gerechnet,
        // denn genau die unzulaessige Menge ist ja die Aussage.
        let pctRoh = hefeFrischPct(nettoStunden: Double(netto) / 60,
                                   raumtemp: c.raumtempC, mehltyp: c.mehltyp, k: c.kFaktor)
        let x = zehntel(mehlGrammRoh(config: c, hefeFrischPct: pctRoh) * pctRoh / 100)
        let text = "Bei \(grad(c.raumtempC)) °C Raumtemperatur und \(stunden(netto)) Zeitfenster wären "
            + "\(hefeGramm(x)) g Frischhefe nötig – über der Geschmacksgrenze."

        if let tStrich = kleinsteTauglicheRaumtemp(config: c, essen: essen, calendar: calendar) {
            var waermer = c
            waermer.raumtempC = tStrich
            if let netto2 = loese(config: waermer, essen: essen, calendar: calendar).gewaehlt {
                let y = zutaten(config: waermer, nettoMinuten: netto2).hefeFrischG
                return PizzaProblem(
                    titel: "Zu viel Hefe nötig",
                    text: text,
                    vorschlag: "Empfehlung: Gare bei \(grad(tStrich)) °C (Backofenlampe) – dann reichen \(hefeGramm(y)) g Frischhefe.")
            }
        }
        return PizzaProblem(titel: "Zu viel Hefe nötig",
                            text: text,
                            vorschlag: "Essenszeit später legen – ein längeres Gärfenster braucht weniger Hefe.")
    }

    /// Fall (b): kein einziger Kandidat bringt alle Handgriffe in die Wachzeit.
    private static func problemNachtruhe(config c: PizzaConfig, ab: Date, calendar: Calendar) -> PizzaProblem {
        let text = "Mit der Nachtruhe von \(c.schlafVonHHmm) bis \(c.schlafBisHHmm) fällt bei jeder "
            + "möglichen Gärdauer mindestens ein Handgriff in den Schlaf."
        if let e = fruehesteEssenszeit(config: c, ab: ab, calendar: calendar) {
            return PizzaProblem(titel: "Passt nicht in die Wachzeit",
                                text: text,
                                vorschlag: "Frühestmögliche Essenszeit: \(datumUndUhrzeit(e, calendar: calendar)).")
        }
        return PizzaProblem(titel: "Passt nicht in die Wachzeit",
                            text: text,
                            vorschlag: "In den nächsten 48 Stunden findet sich kein Fenster – Nachtruhe verkürzen.")
    }

    /// Vorlauf-Validierung: unter 4,5 h ist selbst die kuerzeste Gare nicht unterzubringen.
    private static func problemZuFrueh(config c: PizzaConfig, ab: Date, calendar: Calendar) -> PizzaProblem {
        let text = "Ein neapolitanischer Teig braucht mindestens 4,5 Stunden vom ersten Handgriff bis zur Pizza."
        if let e = fruehesteEssenszeit(config: c, ab: ab, calendar: calendar) {
            return PizzaProblem(titel: "Zu kurzfristig",
                                text: text,
                                vorschlag: "Frühestmögliche Essenszeit: \(datumUndUhrzeit(e, calendar: calendar)).")
        }
        return PizzaProblem(titel: "Zu kurzfristig",
                            text: text,
                            vorschlag: "In den nächsten 48 Stunden findet sich kein Fenster – Nachtruhe verkürzen.")
    }

    // MARK: - Zeit-Helfer

    private static func plus(_ minuten: Int, _ d: Date, _ calendar: Calendar) -> Date {
        calendar.date(byAdding: .minute, value: minuten, to: d) ?? d.addingTimeInterval(Double(minuten) * 60)
    }

    private static func auf5MinutenAufrunden(_ d: Date, calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        let angebrochen = calendar.component(.second, from: d) > 0 || calendar.component(.nanosecond, from: d) > 0
        let rest = (comps.minute ?? 0) % 5
        comps.second = 0
        guard let abgeschnitten = calendar.date(from: comps) else { return d }
        // Bei rest == 0 aber angebrochener Minute darf nicht in die Vergangenheit gerundet werden.
        let auf = rest == 0 ? (angebrochen ? 5 : 0) : 5 - rest
        return plus(auf, abgeschnitten, calendar)
    }

    private static func begrenztesNetto(_ n: Int) -> Int {
        min(max(n, PizzaKonstanten.nettoMin), PizzaKonstanten.nettoMax)
    }

    private static func zehntel(_ v: Double) -> Double { (v * 10).rounded() / 10 }

    // MARK: - Formatierung
    //
    // Die Views duerfen NICHT selbst formatieren: SwiftUI interpretiert Text("\(int)") als
    // LocalizedStringKey und setzt einen Tausenderpunkt (aus 2026 wird 2.026). Wer diese
    // Helfer benutzt, kann in die Falle nicht laufen - sie liefern fertige Strings.

    private static func zahl(_ v: Double, nachkommaMin: Int, nachkommaMax: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.numberStyle = .decimal
        f.minimumFractionDigits = nachkommaMin
        f.maximumFractionDigits = nachkommaMax
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.\(nachkommaMax)f", v)
    }

    /// Ganze Gramm - hier ist der Tausenderpunkt korrekt (1.100 g Mehl).
    static func gramm(_ v: Double) -> String { zahl(v.rounded(), nachkommaMin: 0, nachkommaMax: 0) }

    /// Hefe auf 0,1 g genau.
    static func hefeGramm(_ v: Double) -> String { zahl(zehntel(v), nachkommaMin: 1, nachkommaMax: 1) }

    static func prozent(_ v: Double) -> String { zahl(v, nachkommaMin: 2, nachkommaMax: 2) }

    /// Temperatur ohne unnoetige Nachkommastelle: 22 bzw. 22,5.
    static func grad(_ v: Double) -> String { zahl(v, nachkommaMin: 0, nachkommaMax: 1) }

    /// 305 -> "5 h 5 min", 45 -> "45 min", 360 -> "6 h".
    static func dauer(_ minuten: Int) -> String {
        let h = minuten / 60
        let m = minuten % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h) h" }
        return "\(h) h \(m) min"
    }

    /// 305 -> "5,1 h" - fuer Fliesstext, wo eine Zahl reicht.
    static func stunden(_ minuten: Int) -> String {
        zahl(Double(minuten) / 60, nachkommaMin: 1, nachkommaMax: 1) + " h"
    }

    static func uhrzeit(_ d: Date, calendar: Calendar = .current) -> String {
        formatiere(d, muster: "HH:mm", calendar: calendar)
    }

    static func datumUndUhrzeit(_ d: Date, calendar: Calendar = .current) -> String {
        formatiere(d, muster: "EE dd.MM., HH:mm", calendar: calendar)
    }

    private static func formatiere(_ d: Date, muster: String, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = muster
        return f.string(from: d)
    }
}
