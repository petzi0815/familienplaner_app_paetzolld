import SwiftUI

// Keller-Sicht: was steht wirklich im Haus. Bewusst KEINE zweite Katalogliste (das ist
// `WeinListView`), sondern eine Bestandsansicht — nach Lagerort gruppiert, Flaschen direkt in der
// Zeile hoch- und runterzaehlbar, damit das Nachtragen nach dem Oeffnen einer Flasche zwei
// Sekunden dauert und nicht den Umweg ueber die Detailseite braucht.
//
// Darueber die Summenzeile und zwei Hinweisabschnitte, die den Bestand zum Sprechen bringen:
//   "Jetzt trinkreif"  — trinkfenster_bis endet in den naechsten 2 Jahren (oder ist schon vorbei),
//   "Letzte Flasche"   — bestand == 1, also beim naechsten Einkauf mitdenken.
//
// Die Zeile ist absichtlich KEIN NavigationLink: ein Link mit zwei Knoepfen darin ist in einer
// `List` unzuverlaessig, und hier zaehlt das Zaehlen. Der Weg ins Detail bleibt der Alle-Tab.
// Zusaetzlich zu den Zaehl-Knoepfen liegen die beiden haeufigsten Bestands-Aenderungen als
// Wisch-Aktionen an der Zeile („−1" und „Leer") — derselbe Handgriff wie in der Katalogliste.
//
// Seit den Spirituosen zeigt die Zeile zusaetzlich Fuellstand und "angebrochen": eine offene
// Whiskyflasche steht Monate an der Bar, und ob noch ein Drittel drin ist, entscheidet ueber den
// naechsten Einkauf genauso wie die Flaschenzahl. Gesetzt wird der Fuellstand ueber das
// Kontextmenue der Zeile — derselbe Gedanke wie beim Zaehler: zwei Sekunden statt Umweg ueber die
// Detailseite.
//
// Der Keller folgt dem Art-Umschalter im Kopf wie der ganze Bereich: er zeigt entweder den
// Weinkeller oder die Bar, nie beides. Anders ginge es nicht — das Segment darueber traegt bereits
// einen art-gefilterten Zaehler ("Keller (3)"), und eine Ansicht, die dazu acht Flaschen inklusive
// Whisky zeigt, widerspraeche ihrem eigenen Reiter. Alle Beschriftungen leiten sich deshalb aus
// `store.art` ab und duerfen die Getraenkeart beim Namen nennen.
//
// Seit dem Standort hat der Keller eine Gruppe, die kein Regal ist: „🏢 Im Büro" sammelt die dort
// geparkten Flaschen UNABHAENGIG von ihrem Lagerort und nimmt sie der Regal-Gruppierung weg — die
// Regale zu Hause sollen nur zeigen, was auch wirklich zu Hause steht. Verschwinden tut dabei
// nichts: in Bestand, Kennzahlen und den beiden Hinweisabschnitten zaehlen die geparkten Flaschen
// voll mit, die Summenzeile nennt sie lediglich zusaetzlich getrennt.

/// Eine Gruppe der Keller-Liste — im Normalfall ein Lagerort, dazu die beiden Sammel-Gruppen
/// „Ohne Lagerort" und „Im Büro", die `rang` ans Ende sortiert.
/// `id` traegt den Rang mit: ein frei getippter Lagerort „Im Büro" haette sonst dieselbe Kennung
/// wie die Buero-Gruppe, und `ForEach` saehe zwei Abschnitte mit gleicher ID.
private struct WeinKellerGruppe: Identifiable {
    var id: String { String(rang) + "-" + lagerort }
    let lagerort: String
    let weine: [Wein]
    /// Zeichen vor der Ueberschrift — Regale tragen die Kiste, die Buero-Gruppe ihr Haus.
    var emoji: String = "📦"
    /// Sortier-Rang der Gruppe (Begruendung der Reihenfolge steht in `gruppen`).
    let rang: Int
    var flaschen: Int { weine.reduce(0) { $0 + $1.bestand } }
}

/// Eine waehlbare Fuellstand-Stufe des Kontextmenues. Eigener Typ statt Tupel, weil `ForEach`
/// einen Identifier braucht und Swift keine Key-Paths auf Tupel-Elemente kennt.
private struct WeinKellerStufe: Identifiable {
    var id: Int { prozent }
    let prozent: Int
    let text: String
}

struct WeinKellerView: View {
    @EnvironmentObject private var store: WeinStore

    /// Ohne Lagerort erfasste Flaschen landen gesammelt am Ende.
    private static let ohneLagerort = "Ohne Lagerort"

    // Sortier-Raenge der Gruppen — ausgeschrieben statt als Zahlen im Vergleich, damit die
    // Reihenfolge an einer Stelle nachzulesen ist (angewendet in `gruppen`).
    private static let rangRegal = 0
    private static let rangBuero = 1
    private static let rangSammel = 2

    /// Nur die aktuell gewaehlte Getraenkeart — der Umschalter im Kopf gilt fuer den GANZEN Bereich.
    /// Ohne diese Einschraenkung widerspraechen sich Kopf und Inhalt: das Segment darueber zaehlt
    /// „Keller (3)" bereits art-gefiltert, waehrend hier acht Flaschen inklusive Whisky staenden.
    private var imKeller: [Wein] { store.weine.filter { $0.bestand > 0 && $0.art == store.art } }

    /// Die Regal-Gruppen entstehen NUR aus dem, was zu Hause steht — die geparkten Flaschen nimmt
    /// `bueroGruppe` vorher heraus. Sonst stuende unter „Bar" eine Flasche, die im Buero liegt,
    /// und genau dieses vergebliche Suchen soll der Standort ersparen.
    private var gruppen: [WeinKellerGruppe] {
        let gruppiert = Dictionary(grouping: imKeller.filter { !$0.istImBuero }) { w -> String in
            let l = (w.lagerort ?? "").trimmingCharacters(in: .whitespaces)
            return l.isEmpty ? Self.ohneLagerort : l
        }
        var alle = gruppiert.map {
            WeinKellerGruppe(lagerort: $0.key,
                             weine: $0.value.sorted { $0.titel < $1.titel },
                             rang: $0.key == Self.ohneLagerort ? Self.rangSammel : Self.rangRegal)
        }
        if let buero = bueroGruppe { alle.append(buero) }
        return alle.sorted { a, b in
            // Bestehende Regel der Datei: der Sammel-Eimer steht immer hinten, benannte Regale
            // davor alphabetisch. Die Buero-Gruppe schiebt sich zwischen beide — sie IST eine
            // Ortsangabe (man weiss, wo die Flasche steht), waehrend der Eimer nur sagt, dass der
            // Ort unbekannt ist; hinter die Regale gehoert sie trotzdem, weil sie keines im Haus ist.
            if a.rang != b.rang { return a.rang < b.rang }
            return a.lagerort.localizedCaseInsensitiveCompare(b.lagerort) == .orderedAscending
        }
    }

    /// Die geparkten Flaschen als eigene Gruppe — unabhaengig vom Lagerort, deshalb ausserhalb der
    /// Gruppierung gebaut. nil, wenn nichts im Buero steht: dann fehlt der Abschnitt ersatzlos.
    /// Sie laeuft durch dieselbe `ForEach` wie die Regale und behaelt damit die kanonische
    /// Zeilen-Kennung (`wein-keller-…`); eindeutig bleibt die, weil eine Flasche entweder geparkt
    /// ODER in einer Regal-Gruppe steht — nie in beiden.
    private var bueroGruppe: WeinKellerGruppe? {
        guard !imBuero.isEmpty else { return nil }
        return WeinKellerGruppe(lagerort: WeinStandort.buero.label,
                                weine: imBuero.sorted { $0.titel < $1.titel },
                                emoji: WeinStandort.buero.emoji,
                                rang: Self.rangBuero)
    }

    /// Im Buero geparkte Flaschen der angezeigten Getraenkeart. Die Spalte gilt fuer beide Arten —
    /// seit dem Umschalter im Kontextmenue an JEDER Zeile (nicht mehr nur an Spirituosen) auch die
    /// Bedienung dazu: geparkt wird, was zu Hause keinen Platz hat, und das ist bei einer Kiste
    /// Barolo nicht anders als bei einer Kiste Whisky.
    private var imBuero: [Wein] { imKeller.filter { $0.istImBuero } }

    private var flaschenGesamt: Int { imKeller.reduce(0) { $0 + $1.bestand } }

    /// FLASCHEN (nicht Eintraege) im Buero — Grundlage des Zusatzes in der Summenzeile.
    private var flaschenImBuero: Int { imBuero.reduce(0) { $0 + $1.bestand } }

    /// Die Ansicht zeigt seit dem Umschalter immer genau EINE Getraenkeart (siehe `imKeller`),
    /// deshalb duerfen die Beschriftungen sie beim Namen nennen statt neutral zu bleiben.
    private var eineArt: GetraenkeArt { store.art }

    /// Beschriftung der zweiten Kachel: sie zaehlt EINTRAEGE, nicht Flaschen.
    private var sortenLabel: String { eineArt == .spirituose ? "Spirituosen" : "Weine" }

    /// Wort fuer einen Zaehler in einem Satz ("für 3 Weine").
    private func eintragWort(_ anzahl: Int) -> String {
        if eineArt == .spirituose { return anzahl == 1 ? "Spirituose" : "Spirituosen" }
        return anzahl == 1 ? "Wein" : "Weine"
    }

    /// Geschaetzter Kellerwert ueber den Referenzpreis. Weine ohne Referenzpreis fehlen darin —
    /// deshalb steht die Einschraenkung als Fusszeile unter der Summe.
    private var wertGesamt: Double {
        imKeller.reduce(0) { summe, w in summe + (w.referenzpreis ?? 0) * Double(w.bestand) }
    }
    private var ohnePreis: Int { imKeller.filter { $0.referenzpreis == nil }.count }

    /// Trinkfenster endet in den naechsten 2 Jahren (oder ist bereits abgelaufen).
    private var trinkreif: [Wein] {
        let jahr = Calendar.current.component(.year, from: Date())
        return imKeller
            .filter { w in
                guard let bis = w.trinkfensterBis else { return false }
                return bis <= jahr + 2
            }
            .sorted { ($0.trinkfensterBis ?? 0) < ($1.trinkfensterBis ?? 0) }
    }

    private var letzteFlasche: [Wein] {
        imKeller.filter { $0.bestand == 1 }.sorted { $0.titel < $1.titel }
    }

    var body: some View {
        Group {
            if imKeller.isEmpty {
                // `List` rendert Leerzustaende schlecht → eigener scrollbarer Zweig (Pull-to-Refresh bleibt).
                ScrollView {
                    AreaEmptyState(emoji: "🍷",
                                   title: "Keller ist leer",
                                   hint: "Trage bei einem Wein oder einer Spirituose den Bestand ein, "
                                       + "dann taucht die Flasche hier auf.")
                        .frame(maxWidth: .infinity).frame(minHeight: 300)
                        .accessibilityIdentifier("wein-keller-empty")
                }
                .refreshable { await store.reload() }
            } else {
                liste
            }
        }
    }

    private var liste: some View {
        List {
            Section { summe }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if !trinkreif.isEmpty {
                Section {
                    ForEach(trinkreif) { zeile($0, hinweis: trinkfensterHinweis($0), praefix: "wein-keller-reif") }
                } header: {
                    kopf("⏳ Jetzt trinkreif", trinkreif.count)
                        .accessibilityIdentifier("wein-keller-trinkreif")
                } footer: {
                    Text("Das Trinkfenster endet in den nächsten zwei Jahren.")
                }
                .textCase(nil)
            }

            if !letzteFlasche.isEmpty {
                Section {
                    ForEach(letzteFlasche) { zeile($0, hinweis: "Letzte Flasche", praefix: "wein-keller-rest") }
                } header: {
                    kopf("🔔 Letzte Flasche", letzteFlasche.count)
                        .accessibilityIdentifier("wein-keller-letzte")
                } footer: {
                    Text("Beim nächsten Einkauf mitdenken.")
                }
                .textCase(nil)
            }

            ForEach(gruppen) { g in
                Section {
                    ForEach(g.weine) { zeile($0, hinweis: nil) }
                } header: {
                    kopf(g.emoji + " " + g.lagerort, g.flaschen, einheit: "Flaschen")
                }
                .textCase(nil)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await store.reload() }
        // KEIN Container-Identifier auf der List: er wuerde auf saemtliche Zeilen, Kopfzeilen und
        // Zaehl-Knoepfe durchschlagen. Anker sind die Kopfzeilen und die Zeilen-Titel.
    }

    // MARK: - Summenzeile

    private var summe: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                AreaStatTile(value: String(flaschenGesamt), label: "Flaschen", color: Color(hex: "7C3AED"))
                AreaStatTile(value: String(imKeller.count), label: sortenLabel, color: Color(hex: "DB2777"))
                // Ohne Nachkommastellen — die Kachel ist schmal. `WeinText.zahl` haelt den
                // Tausenderpunkt aus dem Text heraus.
                AreaStatTile(value: WeinText.zahl(wertGesamt, stellen: 0) + " €",
                             label: "Wert (ca.)", color: Color(hex: "EA580C"))
            }
            // Die geparkten Flaschen stecken in den Kacheln mit drin — sie gehoeren zum Bestand.
            // Deshalb hier der Zusatz, WIE VIELE davon nicht zu Hause stehen. Steht nichts im Buero,
            // entfaellt die Zeile ersatzlos: ein „davon 0 im Büro" waere nur Ballast.
            if flaschenImBuero > 0 {
                Text(WeinStandort.buero.emoji + " Davon " + String(flaschenImBuero)
                     + (flaschenImBuero == 1 ? " Flasche" : " Flaschen") + " im Büro geparkt.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if ohnePreis > 0 {
                Text("Für " + String(ohnePreis) + " " + eintragWort(ohnePreis)
                     + " ist kein Referenzpreis hinterlegt — der fehlt im Wert.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .accessibilityIdentifier("wein-keller-summe")
    }

    private func kopf(_ titel: String, _ anzahl: Int, einheit: String? = nil) -> some View {
        let zusatz = einheit.map { " (" + String(anzahl) + " " + $0 + ")" } ?? (" (" + String(anzahl) + ")")
        return Text(titel + zusatz)
            .font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(.secondary)
    }

    // MARK: - Zeile mit Flaschen-Zaehler

    /// `praefix` haelt die Kennungen eindeutig: derselbe Wein steht oft in mehreren Abschnitten
    /// (trinkreif UND letzte Flasche UND seinem Lagerort), und eine reine Wein-ID gaebe es dann
    /// mehrfach — `app.buttons["wein-keller-minus-5"]` waere im XCUITest mehrdeutig. Die
    /// Lagerort-Gruppe behaelt per Vorgabewert die kanonische Kennung.
    private func zeile(_ w: Wein, hinweis: String?, praefix: String = "wein-keller") -> some View {
        karte(w, hinweis: hinweis, praefix: praefix)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
            // Wischen als zweiter, schneller Weg zum Bestand — dieselben zwei Faelle, die den Keller
            // ueberhaupt ausmachen: eine Flasche entnommen und "die Kiste ist alle". Die Zaehl-
            // Knoepfe in der Zeile bleiben der genaue Weg (auch nach oben); der Wisch spart den
            // Zielvorgang auf ein kleines Symbol, wenn die Hand schon an der Zeile ist.
            // KEIN Vollwisch: beide Aktionen greifen in den Bestand ein, und ein versehentlicher
            // Durchzug haette die naechstliegende — "Leer" — ohne Rueckfrage ausgeloest.
            // Eine Bestandspruefung braucht es hier nicht: im Keller steht nur, was `imKeller` mit
            // `bestand > 0` durchgelassen hat, und der Store meldet den Rest im Klartext.
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    Task { await store.bestandMinusEins(w) }
                } label: {
                    Label("−1", systemImage: "minus.circle")
                }
                .tint(Color(hex: "7C3AED"))
                .accessibilityIdentifier(praefix + "-swipe-minus1-" + String(w.id))

                Button {
                    Task { await store.leeren(w) }
                } label: {
                    Label("Leer", systemImage: "xmark.circle")
                }
                .tint(Color(hex: "DC2626"))
                .accessibilityIdentifier(praefix + "-swipe-leer-" + String(w.id))
            }
    }

    /// Die Karte selbst — mit Kontextmenue an JEDER Zeile, seit der Standort fuer beide Arten gilt.
    /// Frueher hing es nur an Spirituosen, weil ein `.contextMenu` mit leerem Inhalt beim Langdruck
    /// trotzdem eine leere Blase oeffnet und das nach einem Fehler aussaehe; das Menue hat jetzt
    /// aber fuer jede Zeile etwas zu sagen — angebrochen und Fuellstand zeigt der Keller ohnehin
    /// schon bei beiden Arten an (siehe `fuellstandZeile`), und der Umschalter „Im Büro parken"
    /// braucht bei Wein dasselbe Bedienelement wie bei Spirituosen.
    private func karte(_ w: Wein, hinweis: String?, praefix: String) -> some View {
        zeilenInhalt(w, hinweis: hinweis, praefix: praefix)
            .contextMenu { flaschenMenu(w) }
    }

    private func zeilenInhalt(_ w: Wein, hinweis: String?, praefix: String) -> some View {
        HStack(spacing: 12) {
            Text(zeilenEmoji(w)).font(.title3).frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                // Die Zeilen-Kennung sitzt am Titel, NICHT am HStack: ein Container-Identifier
                // propagiert in SwiftUI auf alle Kind-Elemente und ueberschreibt deren eigene IDs
                // (siehe AlarmoTile) — die Zaehl-Knoepfe hiessen dann alle "wein-keller-zeile-N".
                Text(w.titel).font(.subheadline.weight(.semibold)).lineLimit(2)
                    .accessibilityIdentifier(praefix + "-zeile-" + String(w.id))
                HStack(spacing: 6) {
                    einordnung(w)
                    if w.istImBuero {
                        // Auch in der Gruppe „Im Büro", wo die Ueberschrift es schon sagt: dieselbe
                        // Zeile steht weiter oben nochmal unter „Jetzt trinkreif" bzw. „Letzte
                        // Flasche", und dort ist das Abzeichen die einzige Stelle, die den Standort
                        // nennt. Neutrales Schiefergrau wie das Bestands-Abzeichen der Liste — die
                        // Farben der Kategorie-Pille daneben sind belegt und wuerden verwirren.
                        Pill(text: WeinStandort.buero.emoji + " " + WeinStandort.buero.kurz,
                             color: Color(hex: "475569"), filled: false)
                    }
                    if let h = hinweis {
                        Pill(text: h, systemImage: "clock", color: Color(hex: "EA580C"), filled: false)
                    }
                    if let p = w.referenzpreis {
                        Text(WeinText.eur(p)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                fuellstandZeile(w, praefix: praefix)
            }

            Spacer(minLength: 8)

            zaehler(w, praefix: praefix)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Symbol vor der Zeile: Wein zeigt seinen Typ, Spirituosen ihre Kategorie. Ist bei einer
    /// Spirituose keine der 15 Kategorien erkannt, steht das neutrale Glas der Getraenkeart da.
    private func zeilenEmoji(_ w: Wein) -> String {
        w.art == .spirituose ? (w.kategorie?.emoji ?? w.art.emoji) : w.typ.emoji
    }

    /// Einordnungs-Pille: Weintyp bzw. Spirituosen-Kategorie. Ohne erkannte Kategorie steht dort
    /// neutral "Spirituose" — "Sonstiges" waere eine Einordnung, die der Datensatz nicht hergibt.
    @ViewBuilder private func einordnung(_ w: Wein) -> some View {
        if w.art == .spirituose {
            if let k = w.kategorie {
                Pill(text: k.label, color: k.farbe)
            } else {
                Pill(text: w.art.einzahl, color: Color(hex: "6B7280"))
            }
        } else {
            Pill(text: w.typ.label, color: w.typ.farbe)
        }
    }

    // MARK: - Fuellstand / angebrochene Flaschen

    /// Punkt + Balken + Klartext, aber nur wenn es etwas zu zeigen gibt: ein Balken auf 100 % waere
    /// an einer ungeoeffneten Flasche eine Behauptung, die der Datensatz nicht hergibt (aus dem
    /// gleichen Grund liefert `Wein.fuellstandLabel` ohne erfassten Wert nil). Die Zeile gilt fuer
    /// BEIDE Getraenkearten — auch eine angebrochene Weinflasche soll man im Keller sehen —,
    /// gepflegt wird sie in der Praxis an der Bar.
    @ViewBuilder private func fuellstandZeile(_ w: Wein, praefix: String) -> some View {
        if w.istAngebrochen || w.fuellstandProzent != nil {
            HStack(spacing: 6) {
                if w.istAngebrochen {
                    Circle().fill(Color(hex: "EA580C")).frame(width: 7, height: 7)
                }
                if let p = w.fuellstandProzent { balken(p) }
                if let t = fuellstandText(w) {
                    Text(t).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(praefix + "-fuellstand-" + String(w.id))
        }
    }

    /// Schmaler Balken mit FESTER Breite: mit `GeometryReader` wuerde die Zeilenhoehe je nach
    /// Titellaenge springen, und breiter braucht es hier nicht — der Balken ist ein Blickfang,
    /// die genaue Stufe steht als Text daneben.
    private func balken(_ prozent: Int) -> some View {
        let breite: CGFloat = 56
        let anteil = max(0, min(100, prozent))
        return Capsule()
            .fill(Color.primary.opacity(0.12))
            .frame(width: breite, height: 5)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(balkenFarbe(anteil))
                    // Mindestbreite, damit auch "leer" als Strich sichtbar bleibt und der Balken
                    // nicht einfach verschwindet (das saehe aus wie "nicht erfasst").
                    .frame(width: max(3, breite * CGFloat(anteil) / 100), height: 5)
            }
    }

    /// Ampel: fast leere Flaschen sollen im Keller auffallen (nachkaufen), volle nicht.
    private func balkenFarbe(_ prozent: Int) -> Color {
        if prozent <= 15 { return Color(hex: "DC2626") }
        if prozent <= 50 { return Color(hex: "EA580C") }
        return Color(hex: "16A34A")
    }

    /// Klartext neben dem Balken — nie "nil" und nie eine geratene Stufe.
    private func fuellstandText(_ w: Wein) -> String? {
        let stufe = w.fuellstandLabel
        guard w.istAngebrochen else { return stufe }
        return stufe.map { "angebrochen · " + $0 } ?? "angebrochen"
    }

    /// Waehlbare Stufen — dieselben Marken, die `Wein.fuellstandLabel` benennt, damit Menue und
    /// Anzeige nie auseinanderlaufen.
    private static let stufen: [WeinKellerStufe] = [
        WeinKellerStufe(prozent: 100, text: "voll"),
        WeinKellerStufe(prozent: 75, text: "¾ voll"),
        WeinKellerStufe(prozent: 50, text: "halb"),
        WeinKellerStufe(prozent: 25, text: "¼"),
        WeinKellerStufe(prozent: 10, text: "Neige"),
        WeinKellerStufe(prozent: 0, text: "leer"),
    ]

    /// Kontextmenue der Zeile: Flasche oeffnen bzw. wieder als ungeoeffnet markieren, ins Buero
    /// parken und den Fuellstand in Stufen setzen. Haengt an JEDER Zeile (Entscheidung sitzt in
    /// `karte`), nicht mehr nur an Spirituosen: der Standort gilt fuer beide Arten, und wer eine
    /// Kiste Wein im Buero abstellt, braucht denselben Umschalter. Angebrochen und Fuellstand
    /// bleiben in der Praxis Spirituosen-Themen — eine Weinflasche ist am selben Abend leer —,
    /// stehen aber schon immer fuer beide Arten in der Zeile und schaden hier nicht.
    /// Die Zaehl-Knoepfe der Zeile bleiben der Weg fuer alles, was Flaschenzahlen betrifft.
    @ViewBuilder private func flaschenMenu(_ w: Wein) -> some View {
        if w.istAngebrochen {
            Button {
                Task { await store.setAngebrochen(w, false) }
            } label: {
                Label("Als ungeöffnet markieren", systemImage: "arrow.uturn.backward")
            }
        } else {
            Button {
                Task { await store.setAngebrochen(w, true) }
            } label: {
                Label("Flasche öffnen", systemImage: "drop.fill")
            }
        }

        // Der Umschalter steht oben bei den Zustands-Knoepfen und NICHT hinter den sechs
        // Fuellstand-Stufen: er ist dieselbe Zwei-Sekunden-Aktion wie das Zaehlen, und hinter der
        // langen Stufenliste wuerde man ihn beim Umraeumen jedes Mal suchen. Die Beschriftung ist
        // wortgleich mit der Detailseite, damit beide Wege gleich heissen.
        Button {
            Task { await store.setStandort(w, w.istImBuero ? .zuhause : .buero) }
        } label: {
            Label(w.istImBuero ? "Wieder zu Hause" : "Im Büro parken",
                  systemImage: w.istImBuero ? WeinStandort.zuhause.symbol : WeinStandort.buero.symbol)
        }

        Divider()

        // Haken an der aktuellen Stufe, damit man beim zweiten Oeffnen sieht, was gesetzt ist.
        ForEach(Self.stufen) { s in
            Button {
                Task { await store.setFuellstand(w, s.prozent) }
            } label: {
                Label(s.text, systemImage: w.fuellstandProzent == s.prozent ? "checkmark" : "circle")
            }
        }

        // Zuruecknehmen statt raten: "nicht erfasst" ist ein eigener Zustand, kein 0 %.
        if w.fuellstandProzent != nil {
            Divider()
            Button(role: .destructive) {
                Task { await store.setFuellstand(w, nil) }
            } label: {
                Label("Füllstand unbekannt", systemImage: "questionmark.circle")
            }
        }
    }

    /// Flaschen +/- direkt in der Zeile. `.borderless` ist Pflicht: sonst wuerde die `List` die
    /// ganze Zeile als EINEN Knopf behandeln und beide Symbole loesten dasselbe aus.
    private func zaehler(_ w: Wein, praefix: String) -> some View {
        HStack(spacing: 10) {
            Button {
                Task { await store.setBestand(w, max(0, w.bestand - 1)) }
            } label: {
                Image(systemName: "minus.circle.fill").font(.title3)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color(hex: "DC2626"))
            .accessibilityLabel("Eine Flasche weniger")
            .accessibilityIdentifier(praefix + "-minus-" + String(w.id))

            Text(String(w.bestand))
                .font(.headline.monospacedDigit())
                .frame(minWidth: 26)
                .accessibilityIdentifier(praefix + "-bestand-" + String(w.id))

            Button {
                Task { await store.setBestand(w, w.bestand + 1) }
            } label: {
                Image(systemName: "plus.circle.fill").font(.title3)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color(hex: "16A34A"))
            .accessibilityLabel("Eine Flasche mehr")
            .accessibilityIdentifier(praefix + "-plus-" + String(w.id))
        }
    }

    /// Klartext zum Trinkfenster — je nachdem, ob es laeuft, dieses Jahr endet oder vorbei ist.
    private func trinkfensterHinweis(_ w: Wein) -> String {
        guard let bis = w.trinkfensterBis else { return "Trinkreif" }
        let jahr = Calendar.current.component(.year, from: Date())
        if bis < jahr { return "seit " + String(bis) + " über dem Fenster" }
        if bis == jahr { return "nur noch " + String(bis) }
        return "bis " + String(bis)
    }
}
