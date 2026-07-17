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

    /// Frischhefe in Prozent aus warm-aequivalenten Stunden (Integral ueber alle Gaerphasen):
    /// `pct * Σ_i(t_i · r(T_i)) = K / mehlFaktor`. Fuer eine einzige warme Phase ist das
    /// identisch zu `hefeFrischPct` (dort ist Σ = nettoStunden · r(raumtemp)).
    static func hefePctVonIntegral(warmEqStunden: Double, mehltyp: Mehltyp, k: Double) -> Double {
        let nenner = warmEqStunden * mehltyp.mehlFaktor
        guard nenner > 0, nenner.isFinite else { return PizzaKonstanten.hefePctMax + 1 }
        return k / nenner
    }

    // MARK: - Zutaten

    static func zutaten(config: PizzaConfig, nettoMinuten: Int) -> PizzaZutaten {
        let c = config.normalisiert()
        let netto = begrenztesNetto(nettoMinuten)
        let pctRoh = hefeFrischPct(nettoStunden: Double(netto) / 60,
                                   raumtemp: c.raumtempC, mehltyp: c.mehltyp, k: c.kFaktor)
        return zutaten(config: c, pctRoh: pctRoh)
    }

    /// Zutaten zu einem bereits berechneten (ungeclampten) Frischhefe-Prozentsatz. Der Solver der
    /// kalten Variante rechnet die Hefe aus dem warmEq-Integral und reicht sie hier direkt herein.
    static func zutaten(config: PizzaConfig, pctRoh: Double) -> PizzaZutaten {
        let c = config.normalisiert()
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
        // Die kalte Variante liefert fuer diese beiden Schritte ihren eigenen Text (mit Dauer
        // und Kuehlschranktemperatur), weil hier der noetige Kontext fehlt.
        case .kuehlschrank, .anwaermen:
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
    /// das laengere netto (laengere Gare = mehr Aroma). Damit kann der warme Solver beim ersten
    /// Treffer abbrechen - im Normalfall gewinnt der Standardplan in der ersten Runde.
    ///
    /// Einmal berechnet, nicht je Aufruf: die Vorwaertssuche nach der fruehestmoeglichen Essenszeit
    /// ruft `warmPlanIntern` viele Male auf, und die Liste haengt von keiner Eingabe ab.
    private static let kandidatenPrio: [Int] = nettoKandidaten().sorted { a, b in
        let da = abs(a - PizzaKonstanten.nettoStandard)
        let db = abs(b - PizzaKonstanten.nettoStandard)
        if da != db { return da < db }
        return a > b
    }

    // MARK: Nominale Minuten (Wanduhr, 1440/Tag)
    //
    // Die Planungslogik rechnet - wie das validierte Referenzmodell - in ganzen Minuten mit
    // exakt 1440 Minuten pro Tag; die Nachtruhe wird auf der Tagesminute (mod 1440) geprueft.
    // Der Tagesindex kommt aus dem Calendar (DST-sichere Tagesdifferenz), sodass `m % 1440`
    // die WANDUHR-Minute ist. Die Rueckwandlung in ein `Date` addiert Tage UND Minuten wieder
    // ueber den Calendar - damit bleiben die absoluten Zeitpunkte DST-sicher.

    /// Nominale Minute eines Datums relativ zu Referenz-Mitternacht `ref` (= Tagesbeginn von jetzt).
    private static func nominalMin(_ d: Date, ref: Date, calendar: Calendar) -> Int {
        let startD = calendar.startOfDay(for: d)
        let tage = calendar.dateComponents([.day], from: ref, to: startD).day ?? 0
        return tage * PizzaKonstanten.minutenProTag + tagesminute(d, calendar: calendar)
    }

    /// Rueckwandlung nominale Minute -> Date (DST-sicher ueber Tages- und Minutenaddition).
    private static func datum(nominalMin m: Int, ref: Date, calendar: Calendar) -> Date {
        let tag = floorDiv(m, PizzaKonstanten.minutenProTag)
        let rest = m - tag * PizzaKonstanten.minutenProTag
        let tagDate = calendar.date(byAdding: .day, value: tag, to: ref) ?? ref
        return plus(rest, tagDate, calendar)
    }

    /// Ganzzahlige Division, die zur negativen Unendlichkeit abrundet (Swift-`/` schneidet zur Null ab).
    private static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b, r = a % b
        return (r != 0 && (r < 0) != (b < 0)) ? q - 1 : q
    }

    /// Schlaeft die Wanduhr zur nominalen Minute? (Tagesminute gegen das Nachtruhe-Fenster.)
    private static func schlaeftMin(_ m: Int, config c: PizzaConfig) -> Bool {
        guard c.nachtruheAktiv else { return false }
        let t = PizzaConfig.normalisierteTagesminute(m)
        if c.schlafVon < c.schlafBis { return t >= c.schlafVon && t < c.schlafBis }
        return t >= c.schlafVon || t < c.schlafBis
    }

    /// Naechste wache nominale Minute >= m (5-Minuten-Raster).
    private static func naechsteWachzeit(_ m: Int, config c: PizzaConfig) -> Int {
        var t = m
        var i = 0
        while i < 288 * 3 && schlaeftMin(t, config: c) { t += 5; i += 1 }
        return t
    }

    /// Letzter Schlafbeginn (Bettzeit) STRIKT vor der nominalen Minute `m`. `von` = Tagesminute
    /// des Schlafbeginns.
    private static func letzteBettzeitVor(_ m: Int, von: Int) -> Int {
        let tag = floorDiv(m, PizzaKonstanten.minutenProTag)
        var d = tag + 1
        while d >= tag - 4 {
            let cand = d * PizzaKonstanten.minutenProTag + von
            if cand < m { return cand }
            d -= 1
        }
        return m - PizzaKonstanten.minutenProTag
    }

    // MARK: Warm (Same-Day)

    /// Warmer Plan (Raumtemperatur, alles an einem Tag) - die bisherige, schmeckende Logik.
    /// Nil nur, wenn kein wacher Kandidat mit `start >= jetzt` existiert; dann uebernimmt `plan`
    /// den Notfallzweig.
    static func warmPlan(config: PizzaConfig, essen: Date, jetzt: Date, calendar: Calendar = .current) -> PizzaPlan? {
        let c = config.normalisiert()
        let ref = calendar.startOfDay(for: jetzt)
        return warmPlanIntern(config: c, essen: essen,
                              essenMin: nominalMin(essen, ref: ref, calendar: calendar),
                              jetztMin: tagesminute(jetzt, calendar: calendar),
                              calendar: calendar)
    }

    private static func warmPlanIntern(config c: PizzaConfig, essen: Date, essenMin: Int,
                                       jetztMin: Int, calendar: Calendar) -> PizzaPlan? {
        var fallback: (netto: Int, pct: Double)?
        for netto in kandidatenPrio {
            let start = essenMin - PizzaKonstanten.fixSumme - netto
            let stock = stockMinuten(netto)
            let stueck = netto - stock
            if stock < PizzaKonstanten.stockMin || stueck < PizzaKonstanten.stueckMin { continue }
            if start < jetztMin { continue }                                   // nicht in der Vergangenheit
            if warmAktMinuten(config: c, essenMin: essenMin, netto: netto)
                .contains(where: { schlaeftMin($0, config: c) }) { continue }   // Handgriff im Schlaf
            let pct = hefeFrischPct(nettoStunden: Double(netto) / 60,
                                    raumtemp: c.raumtempC, mehltyp: c.mehltyp, k: c.kFaktor)
            if pct <= PizzaKonstanten.hefePctMax {
                return baueWarm(config: c, essen: essen, netto: netto, knapp: false, extra: nil, calendar: calendar)
            }
            // Wach, aber zu viel Hefe -> Fallback mit der KLEINSTEN Ueberschreitung merken.
            if fallback == nil || pct < fallback!.pct { fallback = (netto, pct) }
        }
        if let fb = fallback {
            return baueWarm(config: c, essen: essen, netto: fb.netto, knapp: true, extra: nil, calendar: calendar)
        }
        return nil
    }

    /// Die Handgriff-Zeitpunkte eines warmen Kandidaten als nominale Minuten (fuer die Wach-Pruefung).
    private static func warmAktMinuten(config c: PizzaConfig, essenMin: Int, netto: Int) -> [Int] {
        let start = essenMin - PizzaKonstanten.fixSumme - netto
        let stockStart = start + PizzaKonstanten.fixKneten + PizzaKonstanten.fixEntspannen
        let port = stockStart + stockMinuten(netto)
        var akt = [start, start + PizzaKonstanten.fixKneten, port,
                   essenMin - PizzaKonstanten.fixBacken - PizzaKonstanten.vorheizMin,
                   essenMin - PizzaKonstanten.fixBacken, essenMin]
        if c.mehltyp == .dinkel { akt.append(stockStart + 30); akt.append(stockStart + 60) }
        return akt
    }

    private static func baueWarm(config c: PizzaConfig, essen: Date, netto: Int, knapp: Bool,
                                 extra: PizzaHinweis?, calendar: Calendar) -> PizzaPlan {
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
        // Bei einem knappen Fenster ist die Abweichung schon durch die Mehrhefe erklaert -
        // dann keinen zusaetzlichen (widerspruechlichen) planVerschoben-Hinweis geben.
        if !knapp && netto != PizzaKonstanten.nettoStandard {
            hinweise.append(.planVerschoben(nettoMinuten: netto,
                                            grund: verschiebeGrund(config: c, essen: essen, calendar: calendar)))
        }
        if knapp { hinweise.append(.knappesFensterMehrHefe) }
        if let extra { hinweise.append(extra) }

        return PizzaPlan(config: c,
                         variante: .warm,
                         zutaten: z,
                         schritte: s,
                         nettoMinuten: netto,
                         stockMinuten: stock,
                         stueckMinuten: netto - stock,
                         fridgeMinuten: 0,
                         startzeit: plus(-(PizzaKonstanten.fixSumme + netto), essen, calendar),
                         essenszeit: essen,
                         hinweise: hinweise)
    }

    /// Warum weicht der warme Plan vom 6-h-Standard ab? (Nur gefragt, wenn er abweicht.)
    private static func verschiebeGrund(config c: PizzaConfig, essen: Date, calendar: Calendar) -> PizzaVerschiebeGrund {
        let n = PizzaKonstanten.nettoStandard
        let essenMin = nominalMin(essen, ref: calendar.startOfDay(for: essen), calendar: calendar)
        let wach = !warmAktMinuten(config: c, essenMin: essenMin, netto: n)
            .contains { schlaeftMin($0, config: c) }
        let pct = hefeFrischPct(nettoStunden: Double(n) / 60,
                                raumtemp: c.raumtempC, mehltyp: c.mehltyp, k: c.kFaktor)
        let hefeOk = pct <= PizzaKonstanten.hefePctMax
        switch (wach, hefeOk) {
        case (false, false): return .beides
        case (false, true): return .nachtruhe
        default: return .hefe
        }
    }

    // MARK: Kalt (Kuehlschrankgare, Kugeln kalt ueber Nacht)

    /// Kalter Plan: kneten -> kurze warme Stockgare -> formen -> KUEHLSCHRANK (passiv, ueber Nacht)
    /// -> anwaermen/Stueckgare -> backen. Waehlt fuer mehr Aroma die LAENGSTE Kuehlschrankgare bis
    /// 72 h, die noch an einem Abend mit kneten >= jetzt beginnt. Nil, wenn kein Abend passt.
    static func coldPlan(config: PizzaConfig, essen: Date, jetzt: Date, calendar: Calendar = .current) -> PizzaPlan? {
        let c = config.normalisiert()
        let ref = calendar.startOfDay(for: jetzt)
        return coldPlanIntern(config: c, ref: ref,
                              essenMin: nominalMin(essen, ref: ref, calendar: calendar),
                              jetztMin: tagesminute(jetzt, calendar: calendar),
                              calendar: calendar)
    }

    private static func coldPlanIntern(config c: PizzaConfig, ref: Date, essenMin: Int,
                                       jetztMin: Int, calendar: Calendar) -> PizzaPlan? {
        let fridge = c.fridgeTempC
        let bake = essenMin - PizzaKonstanten.fixBacken
        var warn: [PizzaHinweis] = []

        // 1) Appretto (Anwaermen + Stueckgare) legen; der take-out (Appretto-Start) muss wach sein.
        var appretto = PizzaKonstanten.apprettoIdeal
        var appStart = bake - appretto
        if schlaeftMin(appStart, config: c) {
            let wake = naechsteWachzeit(appStart, config: c)
            appStart = min(wake, bake - PizzaKonstanten.apprettoFloor)
            appretto = bake - appStart
        }
        if appretto < PizzaKonstanten.apprettoMin { warn.append(.kurzeAnwaermzeit) }
        if appretto < PizzaKonstanten.apprettoFloor { return nil }   // Essen mitten in der Nacht
        // Ofen an / backen / essen muessen wach sein (nahe der fixen Essenszeit).
        for m in [essenMin - PizzaKonstanten.fixBacken - PizzaKonstanten.vorheizMin, bake, essenMin] {
            if schlaeftMin(m, config: c) { return nil }
        }

        // 2) Kuehlschrank-Start = ein Abend (Bettzeit). Fuer mehr Aroma die LAENGSTE Gare bis 72 h,
        //    die noch mit kneten >= jetzt an einem Abend beginnt.
        let kneadFix = PizzaKonstanten.fixPortionieren + PizzaKonstanten.bulkIdeal
            + PizzaKonstanten.fixEntspannen + PizzaKonstanten.fixKneten
        var bettzeiten: [Int] = []
        var b = letzteBettzeitVor(appStart, von: c.schlafVon)
        let untergrenze = appStart - PizzaKonstanten.fridgeGareMax - PizzaKonstanten.minutenProTag
        while b > untergrenze { bettzeiten.append(b); b -= PizzaKonstanten.minutenProTag }
        bettzeiten.reverse()   // frueheste zuerst = laengste Gare zuerst
        var fridgeStart: Int?
        var fridgeGare = 0
        for cand in bettzeiten {
            let f = appStart - cand
            if f < PizzaKonstanten.fridgeGareMin || f > PizzaKonstanten.fridgeGareMax { continue }
            if cand - kneadFix < jetztMin { continue }   // kneten laege in der Vergangenheit
            fridgeStart = cand; fridgeGare = f; break     // erster (= laengster) gueltiger gewinnt
        }
        guard let fStart = fridgeStart else { return nil }

        // 3) Abend-Session vor dem Kuehlschrank: kneten -> entspannen -> Stockgare (bulk) -> formen.
        var bulk = PizzaKonstanten.bulkIdeal
        let port = fStart - PizzaKonstanten.fixPortionieren
        var stockStart = port - bulk
        var kneten = stockStart - PizzaKonstanten.fixEntspannen - PizzaKonstanten.fixKneten
        func eveningWach() -> Bool {
            ![kneten, kneten + PizzaKonstanten.fixKneten, port].contains { schlaeftMin($0, config: c) }
        }
        if !eveningWach() {
            // Bulk kuerzen (bis bulkMin), bis alle Abend-Handgriffe wach sind.
            var bb = PizzaKonstanten.bulkIdeal
            while bb >= PizzaKonstanten.bulkMin {
                bulk = bb
                stockStart = port - bulk
                kneten = stockStart - PizzaKonstanten.fixEntspannen - PizzaKonstanten.fixKneten
                if eveningWach() { break }
                bb -= 15
            }
            if !eveningWach() { return nil }
        }
        if kneten < jetztMin { return nil }   // muss in der Zukunft starten

        // 4) Hefe aus dem warmEq-Integral: bulk (warm) + Kuehlschrank (kalt) + appretto (warm).
        let warmEq = Double(bulk + appretto) / 60 * gaerFaktor(c.raumtempC)
            + Double(fridgeGare) / 60 * gaerFaktor(fridge)
        let pctRoh = hefePctVonIntegral(warmEqStunden: warmEq, mehltyp: c.mehltyp, k: c.kFaktor)
        if pctRoh < PizzaKonstanten.hefePctMin { warn.append(.sehrWenigHefe(pctRoh)) }

        return baueKalt(config: c, ref: ref, essenMin: essenMin, kneten: kneten, stockStart: stockStart,
                        bulk: bulk, port: port, fridgeStart: fStart, fridgeGare: fridgeGare,
                        appStart: appStart, appretto: appretto, bake: bake, pctRoh: pctRoh,
                        warn: warn, calendar: calendar)
    }

    private static func baueKalt(config c: PizzaConfig, ref: Date, essenMin: Int, kneten: Int,
                                 stockStart: Int, bulk: Int, port: Int, fridgeStart: Int, fridgeGare: Int,
                                 appStart: Int, appretto: Int, bake: Int, pctRoh: Double,
                                 warn: [PizzaHinweis], calendar: Calendar) -> PizzaPlan {
        let z = zutaten(config: c, pctRoh: pctRoh)
        let wt = wasserTemp(config: c)

        func d(_ m: Int) -> Date { datum(nominalMin: m, ref: ref, calendar: calendar) }
        func schritt(_ art: PizzaSchrittArt, _ m: Int, _ text: String?) -> PizzaSchritt {
            PizzaSchritt(art: art, zeit: d(m), detail: text)
        }
        // Die geteilten Schrittdetails (kneten/portionieren/backen ...) kommen aus `detail`;
        // stock=bulk, stueck=appretto reichen ihm dieselben Kontextwerte wie der warmen Variante.
        func geteilt(_ art: PizzaSchrittArt) -> String? {
            detail(fuer: art, config: c, stock: bulk, stueck: appretto, wasserTemp: wt.temp)
        }

        var schritte: [PizzaSchritt] = [
            schritt(.kneten, kneten, geteilt(.kneten)),
            schritt(.entspannen, kneten + PizzaKonstanten.fixKneten, geteilt(.entspannen)),
            schritt(.stockgare, stockStart, "\(dauer(bulk)) warme Stockgare abgedeckt bei \(grad(c.raumtempC)) °C."),
        ]
        if c.mehltyp == .dinkel {
            schritte.append(schritt(.dehnenFalten1, stockStart + 30, "Teig einmal rundum dehnen und falten."))
            schritte.append(schritt(.dehnenFalten2, stockStart + 60, "Teig einmal rundum dehnen und falten."))
        }
        schritte.append(schritt(.portionieren, port, geteilt(.portionieren)))
        schritte.append(schritt(.kuehlschrank, fridgeStart,
            "Kugeln abgedeckt in den Kühlschrank – läuft über Nacht, \(dauer(fridgeGare)) bei \(grad(c.fridgeTempC)) °C."))
        schritte.append(schritt(.anwaermen, appStart,
            "Kugeln rausnehmen, \(dauer(appretto)) bei \(grad(c.raumtempC)) °C anwärmen und fertig garen."))
        schritte.append(schritt(.ofenAn, essenMin - PizzaKonstanten.fixBacken - PizzaKonstanten.vorheizMin, geteilt(.ofenAn)))
        schritte.append(schritt(.backen, bake, geteilt(.backen)))
        schritte.append(schritt(.essen, essenMin, nil))

        var hinweise: [PizzaHinweis] = []
        if z.wasserTempGeclampt { hinweise.append(.wasserTempGeclampt(z.wasserTempC)) }
        if c.raumtempC < 18 { hinweise.append(.raumtempNiedrig(c.raumtempC)) }
        if c.raumtempC > 28 { hinweise.append(.raumtempHoch(c.raumtempC)) }
        hinweise.append(contentsOf: warn)

        return PizzaPlan(config: c,
                         variante: .kalt,
                         zutaten: z,
                         schritte: schritte,
                         nettoMinuten: bulk + fridgeGare + appretto,
                         stockMinuten: bulk,
                         stueckMinuten: appretto,
                         fridgeMinuten: fridgeGare,
                         startzeit: d(kneten),
                         essenszeit: d(essenMin),
                         hinweise: hinweise)
    }

    // MARK: Solver-Einstieg

    /// Der Solver scheitert NIE: die Essenszeit ist fix. Liefert beide Varianten, wo moeglich;
    /// mindestens eine ist gesetzt, sofern die Essenszeit >= jetzt + 4,5 h liegt.
    static func plan(config: PizzaConfig, essen: Date, jetzt: Date, calendar: Calendar = .current) -> PizzaPlanung {
        let c = config.normalisiert()
        let ref = calendar.startOfDay(for: jetzt)
        let essenMin = nominalMin(essen, ref: ref, calendar: calendar)
        let jetztMin = tagesminute(jetzt, calendar: calendar)

        let warm = warmPlanIntern(config: c, essen: essen, essenMin: essenMin, jetztMin: jetztMin, calendar: calendar)
        let kalt = coldPlanIntern(config: c, ref: ref, essenMin: essenMin, jetztMin: jetztMin, calendar: calendar)
        if warm != nil || kalt != nil {
            return PizzaPlanung(warm: warm, kalt: kalt, fruehestesMoeglichesEssen: nil)
        }

        // Notfall (Deep-Night-Essen, z. B. 03-08 Uhr): best-effort warmer Plan OHNE Wach-Constraint,
        // laengste Gare zuerst, mit ehrlicher Warnung - statt "geht nicht".
        var n = PizzaKonstanten.nettoMax
        while n >= PizzaKonstanten.nettoMin {
            let start = essenMin - PizzaKonstanten.fixSumme - n
            let stock = stockMinuten(n)
            if stock >= PizzaKonstanten.stockMin, n - stock >= PizzaKonstanten.stueckMin, start >= jetztMin {
                let nacht = warmAktMinuten(config: c, essenMin: essenMin, netto: n)
                    .filter { schlaeftMin($0, config: c) }.count
                let notfall = baueWarm(config: c, essen: essen, netto: n, knapp: false,
                                       extra: .nachtHandgriffeUnvermeidbar(nacht), calendar: calendar)
                return PizzaPlanung(warm: notfall, kalt: nil, fruehestesMoeglichesEssen: nil)
            }
            n -= 5
        }

        // Einzig verbleibende physische Grenze: < 4,5 h Vorlauf ab jetzt.
        let ab = max(essen, plus(PizzaKonstanten.minVorlaufMin, jetzt, calendar))
        return PizzaPlanung(warm: nil, kalt: nil,
                            fruehestesMoeglichesEssen: fruehesteEssenszeit(config: c, ab: ab, jetzt: jetzt, calendar: calendar))
    }

    // MARK: - Gegenvorschlaege

    /// Fruehestmoegliche Essenszeit ab `ab`, in 5-Minuten-Schritten, maximal +48 h. Nur fuer den
    /// <4,5-h-Grenzfall gedacht - die Zeit, ab der wieder mindestens eine Variante moeglich ist.
    static func fruehesteEssenszeit(config: PizzaConfig, ab: Date, jetzt: Date, calendar: Calendar = .current) -> Date? {
        let c = config.normalisiert()
        let ref = calendar.startOfDay(for: jetzt)
        let jetztMin = tagesminute(jetzt, calendar: calendar)
        let start = auf5MinutenAufrunden(ab, calendar: calendar)
        let maxSchritte = 48 * 60 / 5
        for i in 0...maxSchritte {
            let kandidat = plus(i * 5, start, calendar)
            let em = nominalMin(kandidat, ref: ref, calendar: calendar)
            if warmPlanIntern(config: c, essen: kandidat, essenMin: em, jetztMin: jetztMin, calendar: calendar) != nil
                || coldPlanIntern(config: c, ref: ref, essenMin: em, jetztMin: jetztMin, calendar: calendar) != nil {
                return kandidat
            }
        }
        return nil
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

    /// Eine kleine Ganzzahl (Anzahl) als String - bewusst OHNE Tausenderpunkt, damit sie gefahrlos
    /// in `Text("...\(...)")` interpoliert werden kann (LocalizedStringKey wuerde sonst gruppieren).
    static func ganzzahl(_ n: Int) -> String { String(n) }

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

    /// Voller Wochentag + Datum ohne Uhrzeit - fuer den Tageswechsel-Header im mehrtaegigen
    /// Zeitplan der kalten Variante, damit jeder Schritt eindeutig einem Tag zuzuordnen ist.
    static func wochentagDatum(_ d: Date, calendar: Calendar = .current) -> String {
        formatiere(d, muster: "EEEE, dd.MM.", calendar: calendar)
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
