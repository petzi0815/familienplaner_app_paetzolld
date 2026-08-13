import SwiftUI

/// Liste des aktiven Segments. `List` statt `ScrollView`, damit es native Wisch-Aktionen gibt
/// (Loeschen + Flasche getrunken); der Karten-Look bleibt ueber transparente Zeilen erhalten
/// (Muster der acht umgebauten Listen dieses Repos).
///
/// Welche Getraenkeart hier steht, entscheidet der Umschalter im Kopf ueber `store.gefiltert` —
/// die Liste selbst filtert nicht danach. Karte und Leerzustand sind trotzdem art-fest gebaut und
/// vertragen einen gemischten Datenbestand.
struct WeinListView: View {
    /// Aktion des Leerzustands — oeffnet das Erfassen-Sheet der Bereichswurzel.
    var onErfassen: () -> Void = {}

    @EnvironmentObject private var store: WeinStore
    @State private var deleteTarget: Wein?

    var body: some View {
        Group {
            if store.gefiltert.isEmpty {
                ScrollView {
                    leerZustand.frame(maxWidth: .infinity).frame(minHeight: 300)
                }
                .refreshable { await store.reload() }
            } else {
                List {
                    ForEach(store.gefiltert) { w in zeile(w) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await store.reload() }
            }
        }
        .confirmationDialog(deleteTarget.map { $0.titel + " löschen?" } ?? "",
                            isPresented: Binding(get: { deleteTarget != nil },
                                                 set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let t = deleteTarget { Task { await store.delete(t) } }
                deleteTarget = nil
            }
            Button("Abbrechen", role: .cancel) { deleteTarget = nil }
        } message: {
            Text(loeschHinweis)
        }
    }

    /// Loeschhinweis mit passendem Artikel. Faellt auf die gerade gewaehlte Art zurueck, weil der
    /// Dialog-Rumpf auch ausgewertet wird, wenn `deleteTarget` schon wieder nil ist.
    private var loeschHinweis: String {
        let art = deleteTarget?.art ?? store.art
        let subjekt = art == .spirituose ? "Die Spirituose" : "Der Wein"
        return subjekt + " wird mit allen Bewertungen und Preisen gelöscht."
    }

    /// Mehrzahl fuer den Fliesstext: `GetraenkeArt.label` liefert fuer Wein bewusst "Wein"
    /// (so steht es am Umschalter), in einem Satz braucht es "Weine".
    private var artMehrzahl: String { store.art == .spirituose ? "Spirituosen" : "Weine" }

    // ── Leerzustand (unterscheidet leerer Bereich / kein Treffer) ──

    private var leerZustand: some View {
        // `filterAktiv` deckt Typ/Kategorie/Rebsorte/Stil/Land/Sterne ab; Suchtext und Segment
        // kommen dazu. Der Umschalter zaehlt bewusst NICHT als Filter: dass es noch keine
        // Spirituose gibt, ist kein Filter-, sondern ein Erfassungs-Zustand — hier gehoert der
        // Knopf zum Erfassen hin, nicht der Rat, die Filter zu lockern.
        let gefiltertLeer = store.filterAktiv || !store.suche.isEmpty || store.tab != .alle
        let aktion: (() -> Void)? = gefiltertLeer ? nil : onErfassen
        let aktionLabel: String? = gefiltertLeer ? nil : store.art.einzahl + " erfassen"
        // Bei Spirituosen steht das Wesentliche auf der Flasche, nicht auf einem Etikett im
        // Wortsinn — deshalb der andere Aufruf.
        let erfassenHinweis = (store.art == .spirituose ? "Flasche fotografieren" : "Etikett fotografieren")
            + " oder Barcode scannen — den Rest ergänzt die KI."
        let hinweis: String = gefiltertLeer
            ? "Andere Filter oder Suchbegriffe probieren."
            : erfassenHinweis
        return AreaEmptyState(
            emoji: gefiltertLeer ? "🔍" : store.art.emoji,
            title: gefiltertLeer ? "Keine Treffer" : "Noch keine " + artMehrzahl + " erfasst",
            hint: hinweis,
            actionLabel: aktionLabel,
            action: aktion
        )
    }

    // ── Zeile: Karte im NavigationLink (antippbare Zelle MUSS ein Button sein) ──

    private func zeile(_ w: Wein) -> some View {
        // Closure-basierter NavigationLink: wertbasierte Links sind in bereits gepushten Views flaky.
        NavigationLink {
            WeinDetailView(wein: w).environmentObject(store)
        } label: {
            WeinKarte(wein: w, meine: store.meine(w), andere: store.andere(w))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wein-" + String(w.id))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { deleteTarget = w } label: {
                Label("Löschen", systemImage: "trash")
            }
            .accessibilityIdentifier("wein-swipe-loeschen-" + String(w.id))
            if w.bestand > 0 {
                // Zwei Stufen, weil beim Inventarisieren beides vorkommt: eine Flasche geleert
                // (haeufig) oder die letzte Restmenge weg (dann will niemand fuenfmal wischen).
                // Beide laufen ueber den Store, der optimistisch setzt und bei Fehlern zurueckdreht.
                Button { Task { await store.leeren(w) } } label: {
                    Label("Leer", systemImage: "xmark.circle")
                }
                .tint(Color(hex: "B45309"))
                .accessibilityIdentifier("wein-swipe-leer-" + String(w.id))
                Button { Task { await store.bestandMinusEins(w) } } label: {
                    Label("Getrunken", systemImage: "wineglass")
                }
                .tint(Color(hex: "7C3AED"))
                .accessibilityIdentifier("wein-swipe-getrunken-" + String(w.id))
            }
        }
    }
}

// MARK: - Karte

/// Listenkarte: Etikettenfoto, Titel, Herkunft/Rebsorte, BEIDE Bewertungen nebeneinander,
/// Typ-Pille, Bestandsbadge und der beste Preis mit Rabatt-Hinweis.
///
/// Art-abhaengig sind Pille (Weintyp bzw. Spirituosen-Kategorie), die Zeile unter dem Titel
/// (Rebsorten bzw. Stil) und der Titel selbst — den bildet `Wein.titel` und setzt bei Spirituosen
/// die Altersangabe an die Stelle des Jahrgangs. Dazu die Markierung fuer angebrochene Flaschen und
/// das Buero-Abzeichen der geparkten Spirituosen: im Laden ist genau das die Frage — die Flaschen
/// sind zwar da, stehen aber nicht zu Hause.
struct WeinKarte: View {
    let wein: Wein
    var meine: WeinBewertung?
    var andere: WeinBewertung?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            etikett
            VStack(alignment: .leading, spacing: 5) {
                Text(wein.titel).font(.subheadline.weight(.semibold)).lineLimit(2)
                zustandsAbzeichen
                if !herkunft.isEmpty {
                    Text(herkunft).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                bewertungen
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                artPille
                if wein.bestand > 0 {
                    Pill(text: String(wein.bestand) + " Fl.", systemImage: "archivebox",
                         color: Color(hex: "475569"), filled: false)
                }
                if wein.istImBuero {
                    // Direkt unter der Flaschenzahl, weil es genau sie einschraenkt: die drei
                    // Flaschen gibt es, nur eben nicht zu Hause. Kein Bestands-Vorbehalt (wie beim
                    // Abzeichen „angebrochen"): geparkt ist eine Eigenschaft des Eintrags.
                    // Fuer BEIDE Getraenkearten: seit dem Umbau laesst sich auch eine Kiste Barolo
                    // im Buero parken, und was geparkt ist, muss im Katalog sichtbar sein — sonst
                    // sucht man sie zu Hause, und genau das soll der Standort ersparen.
                    Pill(text: WeinStandort.buero.emoji + " " + WeinStandort.buero.kurz,
                         color: Color(hex: "475569"), filled: false)
                }
                if wein.istAngebrochen {
                    // Nur der Zustand, ohne Stufe: die Spalte ist schmal. Wie voll die Flasche noch
                    // ist, steht im Keller (Balken) und auf der Detailseite.
                    Pill(text: "angebrochen", systemImage: "drop.fill",
                         color: Color(hex: "EA580C"), filled: false)
                }
                preis
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }

    /// Abzeichen fuer Zeilen, an denen noch etwas offen ist: die Hintergrund-Erkennung laeuft bzw.
    /// ist gescheitert, oder sie haelt die Flasche fuer eine Dublette. Beides sind KEINE Filter und
    /// keine Fehler des Bestands — die Zeile zaehlt ueberall normal mit und traegt nur zusaetzlich
    /// diesen Hinweis.
    /// Sie stehen unter dem Titel und nicht in der rechten Spalte: dort ist es schmal, und genau
    /// diese Zeilen haben sonst nichts zu zeigen (kein Land, keine Rebsorte, keine Bewertung).
    /// Untereinander statt nebeneinander, weil "möglicherweise doppelt" allein schon breit ist.
    /// Zusammengefuehrt wird nie automatisch — der Verweis auf den vorhandenen Eintrag samt Knopf
    /// „Ansehen" steht im Detail, hier waere dafuer kein Platz.
    /// Die aeussere Bedingung ist wichtig: eine leere `VStack` waere zwar unsichtbar, bekaeme in der
    /// umgebenden Spalte aber trotzdem ihren Abstand — jede fertige Karte wuerde dadurch hoeher.
    @ViewBuilder private var zustandsAbzeichen: some View {
        if wein.istUnfertig || wein.istDublette {
            VStack(alignment: .leading, spacing: 4) {
                if wein.istUnfertig {
                    // Text/Farbe/Symbol kommen aus `WeinKiStatus` — dieselbe Quelle wie die
                    // Warteschlangen-Zeile, damit beide Orte nicht auseinanderlaufen.
                    Pill(text: wein.kiStatus.label, systemImage: wein.kiStatus.symbol,
                         color: wein.kiStatus.farbe, filled: false)
                }
                if wein.istDublette {
                    Pill(text: "möglicherweise doppelt", systemImage: "doc.on.doc",
                         color: Color(hex: "EA580C"), filled: false)
                }
            }
        }
    }

    /// Einordnungs-Pille: Weintyp bzw. Spirituosen-Kategorie. Ist bei einer Spirituose keine der
    /// 15 Kategorien erkannt, steht dort neutral "Spirituose" — "Sonstiges" waere eine Einordnung,
    /// die der Datensatz nicht hergibt (deshalb laesst `Wein.kategorie` sie auch nil).
    @ViewBuilder private var artPille: some View {
        if wein.art == .spirituose {
            if let k = wein.kategorie {
                Pill(text: k.emoji + " " + k.label, color: k.farbe)
            } else {
                Pill(text: wein.art.emoji + " " + wein.art.einzahl, color: Color(hex: "6B7280"))
            }
        } else {
            Pill(text: wein.typ.emoji + " " + wein.typ.label, color: wein.typ.farbe)
        }
    }

    /// Herkunft + das, was die Flasche einordnet, in einer Zeile — was da ist, in dieser
    /// Reihenfolge. Rebsorten haben Spirituosen keine; an ihrer Stelle steht der Stil
    /// ("Single Malt Islay"), ersatzweise die Fassreifung.
    private var herkunft: String {
        var teile: [String] = []
        let ort = WeinText.herkunft(land: wein.land, region: wein.region, lage: nil)
        if !ort.isEmpty { teile.append(ort) }
        if wein.art == .spirituose {
            if let stil = wein.stil, !stil.isEmpty { teile.append(stil) }
            else if let fass = wein.fass, !fass.isEmpty { teile.append(fass) }
        } else if !wein.rebsorten.isEmpty {
            teile.append(wein.rebsorten.prefix(2).joined(separator: ", "))
        }
        return teile.joined(separator: " · ")
    }

    /// Platzhalter-Symbol ohne Foto: Weintyp bzw. Spirituosen-Kategorie, sonst das Glas der Art.
    private var platzhalterEmoji: String {
        wein.art == .spirituose ? (wein.kategorie?.emoji ?? wein.art.emoji) : wein.typ.emoji
    }

    private var etikett: some View {
        Group {
            if let path = wein.imagePath {
                // Karten-Etikett rendert 54x72 pt — die Vorschau reicht dafuer, das Original
                // (bis 2000 px) waere hier reine Ladezeit.
                AuthImage(path: path, contentMode: .fill, thumb: 160)
            } else {
                Palette.gradient(for: "wein").opacity(0.20)
                    .overlay(Text(platzhalterEmoji).font(.title2))
            }
        }
        .frame(width: 54, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Beide Bewertungen nebeneinander (L 4 Sterne / E 5 Sterne) — Kernnutzen des Bereichs.
    @ViewBuilder private var bewertungen: some View {
        if meine == nil && andere == nil {
            Text("Noch nicht bewertet").font(.caption2).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 10) {
                if let b = meine { WeinSterne(sterne: b.sterne, kuerzel: WeinText.kuerzel(b.owner)) }
                if let b = andere { WeinSterne(sterne: b.sterne, kuerzel: WeinText.kuerzel(b.owner)) }
            }
        }
    }

    /// Bester gefundener Preis; liegt er spuerbar unter dem Referenzpreis, kommt der Rabatt davor.
    @ViewBuilder private var preis: some View {
        if let best = wein.besterPreis {
            HStack(spacing: 5) {
                if let r = wein.rabattProzent, r >= 5 {
                    Pill(text: WeinText.rabatt(r), systemImage: "tag.fill", color: Color(hex: "16A34A"))
                }
                Text(WeinText.eur(best)).font(.caption.weight(.semibold))
            }
        } else if let ref = wein.referenzpreis {
            Text(WeinText.eur(ref)).font(.caption).foregroundStyle(.secondary)
        }
    }
}
