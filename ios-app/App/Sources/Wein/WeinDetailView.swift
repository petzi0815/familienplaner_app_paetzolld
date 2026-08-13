import SwiftUI

/// Detailseite eines Weins: Stammdaten, Geschmacksprofil, Hintergrund, Keller, Preise —
/// und der Bewertungsblock, in dem die eigene Bewertung bearbeitbar und die der anderen
/// Person daneben lesbar ist.
///
/// Der angezeigte Datensatz wird ueber `store.weine` nachgeschlagen (`current`), damit
/// Bestandsaenderungen, Bewertungen und Preisergebnisse sofort sichtbar sind.
///
/// ART-ABHAENGIG (seit Migration 0022): Geschmacksprofil, Rebsorten, Geschmacksrichtung und
/// Trinkfenster gibt es NUR beim Wein; Kategorie/Stil/Alter/Fass/Abfuelljahr, Trinkempfehlung,
/// Cocktails und der Fuellstand NUR bei der Spirituose. Bewertungen, Keller, Preise, Historie,
/// Foto und der Standort (Abzeichen im Kopf UND Umschalter im Keller-Block) sind fuer beide Arten
/// identisch — sie sind der Grund, warum beide in EINER Tabelle liegen. Kein Abschnitt darf leer
/// erscheinen: fehlt ein Wert, faellt die Zeile weg.
///
/// „Bearbeiten" in der Toolbar oeffnet die Erfassungsmaske im Bearbeiten-Modus (`bearbeitenSheet`);
/// dort ist auch eine falsche Klassifikation (Weinart bzw. Kategorie) korrigierbar.
struct WeinDetailView: View {
    let wein: Wein

    @EnvironmentObject private var store: WeinStore
    @State private var sterne = 0
    @State private var kommentar = ""
    @State private var speichert = false
    @State private var pruefe = false
    @State private var vorbereitet = false
    /// Bearbeiten-Sheet (dieselbe Maske wie beim Anlegen, siehe `bearbeitenSheet`).
    @State private var bearbeiten = false

    private var current: Wein { store.weine.first { $0.id == wein.id } ?? wein }
    private var tint: Color { Palette.colors(for: "wein").first ?? Theme.accent }
    private var preise: [WeinPreis] { store.preise[current.id] ?? [] }

    /// Akkusativ fuer Fliesstext ("… hat diese Spirituose noch nicht bewertet"). Eigene Property,
    /// weil `GetraenkeArt.einzahl` nur das nackte Wort liefert und der Artikel sich unterscheidet.
    private var diesesGetraenk: String {
        current.art == .spirituose ? "diese Spirituose" : "diesen Wein"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                kopf
                erkennungsblock
                bewertungsblock
                stammdaten
                geschmacksprofil
                aromen
                // Gruppiert, weil ein ViewBuilder-Block hoechstens zehn Kinder aufnimmt.
                Group {
                    trinkempfehlung
                    cocktails
                    hintergrund
                    auszeichnungen
                    trinkfenster
                    kellerBlock
                    fuellstandBlock
                    preisBlock
                    notizen
                }
            }
            .padding(16)
        }
        .background(Palette.gradient(for: "wein").opacity(0.05).ignoresSafeArea())
        // Ohne Namen (Flasche wartet noch auf die Erkennung) traegt der Titel `Wein.titel` —
        // "Wird erkannt …" statt einer leeren Leiste.
        .navigationTitle(current.name.isEmpty ? current.titel : current.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await ersteLadung() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Bearbeiten") { bearbeiten = true }
                    .accessibilityIdentifier("wein-bearbeiten")
            }
        }
        .sheet(isPresented: $bearbeiten) { bearbeitenSheet }
        .areaToast($store.message, isError: store.messageIsError)
    }

    /// Bearbeitet wird in DERSELBEN Maske wie beim Anlegen (`WeinPruefenView`): dort stehen alle
    /// art-abhaengigen Feldgruppen schon, eine zweite Maske liefe binnen einer Aenderung auseinander.
    /// Sie bringt keinen NavigationStack mit (im Erfassungs-Fluss lebt sie im Stack des Sheets) —
    /// hier stellt ihn deshalb das Sheet. Der Store wird ausdruecklich mitgegeben: Sheets erben die
    /// EnvironmentObjects ihres Aufrufers nicht verlaesslich (gleiches Muster wie in `WeinRootView`).
    /// Uebergeben wird `current` und nicht `wein`: der Store haelt den frischen Stand, `wein` ist
    /// nur der Wert, mit dem die Seite einmal geoeffnet wurde.
    private var bearbeitenSheet: some View {
        NavigationStack {
            WeinPruefenView(bearbeiten: current, schliessen: { bearbeiten = false })
                .environmentObject(store)
        }
    }

    // ── Laden / Speichern ──

    private func ersteLadung() async {
        guard !vorbereitet else { return }
        vorbereitet = true
        if let b = store.meine(current) {
            sterne = b.sterne
            kommentar = b.kommentar
        }
        await store.loadPreise(current)
    }

    private func bewertungSpeichern() async {
        guard sterne >= 1 else { return }
        speichert = true
        await store.bewerten(current, sterne: sterne, kommentar: kommentar)
        speichert = false
    }

    private func preisPruefen() async {
        pruefe = true
        await store.preischeck(current)
        await store.loadPreise(current)
        pruefe = false
    }

    // ── Bausteine ──

    /// Abschnitts-Karte mit Ueberschrift — haelt die Detailseite optisch ruhig.
    private func block<Inhalt: View>(_ titel: String, @ViewBuilder _ inhalt: () -> Inhalt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titel).font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(.secondary)
            inhalt()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // ── Kopf ──

    private var kopf: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let path = current.imagePath {
                AuthImage(path: path, contentMode: .fit)
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 320)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Text(current.titel).font(.title3.weight(.bold))
            FlowLayout(spacing: 6) {
                // Beim Wein Typ + Geschmacksrichtung, bei der Spirituose Kategorie + Stil.
                // Fehlt die Kategorie (die Erkennung war sich nicht sicher), bleibt der Platz
                // leer — ein „Sonstiges"-Badge waere eine Behauptung, die niemand aufgestellt hat.
                if current.art == .wein {
                    Pill(text: current.typ.emoji + " " + current.typ.label, color: current.typ.farbe)
                    if current.geschmacksrichtung != "unbekannt" {
                        Pill(text: WeinGeschmack.label(current.geschmacksrichtung), color: tint, filled: false)
                    }
                } else {
                    if let k = current.kategorie {
                        Pill(text: k.emoji + " " + k.label, color: k.farbe)
                    }
                    if let s = current.stil, !s.isEmpty {
                        Pill(text: s, color: tint, filled: false)
                    }
                }
                if current.bio { Pill(text: "Bio", systemImage: "leaf.fill", color: Color(hex: "16A34A")) }
                if current.vegan { Pill(text: "Vegan", systemImage: "carrot.fill", color: Color(hex: "65A30D")) }
                if current.bestand > 0 {
                    Pill(text: String(current.bestand) + " Flaschen", systemImage: "archivebox",
                         color: Color(hex: "475569"), filled: false)
                }
                // Geparkt gehoert NEBEN die Flaschenzahl in den Kopf und nicht nur in die Zeile
                // weiter unten: „3 Flaschen" ohne den Zusatz laedt genau zu der Suche zu Hause ein,
                // die das Feature verhindern soll. Gefuellt, damit es die einzige Pille ist, die
                // hier eine Einschraenkung ausspricht.
                // Fuer beide Getraenkearten — wie der Umschalter im Keller-Block, der inzwischen
                // ebenfalls bei beiden steht: ein geparkter Wein darf auf seiner eigenen
                // Detailseite nicht so aussehen, als staende er zu Hause.
                if current.istImBuero {
                    Pill(text: current.standort.emoji + " " + current.standort.label,
                         color: Color(hex: "0369A1"))
                }
                // Wartet die Flasche noch auf die Hintergrund-Erkennung (oder ist sie daran
                // gescheitert), steht das hier — sonst wirkt eine Karte ohne Weingut, Land und
                // Preis wie ein kaputter Datensatz statt wie einer, der gleich fertig ist.
                if current.istUnfertig {
                    Pill(text: current.kiStatus.label, systemImage: current.kiStatus.symbol,
                         color: current.kiStatus.farbe)
                }
                if current.istDublette {
                    Pill(text: "möglicherweise doppelt", systemImage: "doc.on.doc",
                         color: Color(hex: "C2410C"))
                }
            }
            // Die Lage ist eine reine Weinangabe (Einzellage) — bei Spirituosen bliebe sie ohnehin
            // leer, wird aber gar nicht erst abgefragt, damit ein Altbestand nichts durchreicht.
            let ort = WeinText.herkunft(land: current.land, region: current.region,
                                        lage: current.art == .wein ? current.lage : nil)
            if !ort.isEmpty {
                Label(ort, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // ── Hintergrund-Erkennung ──

    /// Steht nur da, solange es etwas zu sagen gibt: waehrend die Erkennung laeuft, nach einem
    /// Fehlschlag oder wenn ein aehnlicher Eintrag vermutet wird. Bei einer fertig erkannten,
    /// eindeutigen Flasche — dem Normalfall — faellt der ganze Block weg.
    @ViewBuilder private var erkennungsblock: some View {
        if current.istUnfertig || current.istDublette {
            block("Erkennung") {
                VStack(alignment: .leading, spacing: 10) {
                    erkennungsText
                    if let id = current.dubletteVon { dublettenZeile(id) }
                }
            }
        }
    }

    @ViewBuilder private var erkennungsText: some View {
        if current.kiStatus == .fehler {
            // Der Klartext des Servers, wenn es einen gibt — ohne ihn sucht man den Fehler bei der
            // Flasche statt beim fehlenden Schluessel oder beim unlesbaren Etikett.
            Text(current.kiFehler.map { "Fehler: " + $0 } ?? current.kiStatus.label)
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Über Bearbeiten lässt sich die Flasche von Hand ausfüllen oder erneut erkennen.")
                .font(.caption).foregroundStyle(.secondary)
        } else if current.istUnfertig {
            Text("Etikett und Preise werden im Hintergrund ergänzt. Das dauert einen Moment.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    /// Verweis auf den vermuteten vorhandenen Eintrag. Zusammengefuehrt wird NIE automatisch —
    /// zwei Flaschen desselben Weins sind der Normalfall; entscheiden muss das ein Mensch, und
    /// dafuer muss er den anderen Eintrag erst einmal ansehen koennen.
    @ViewBuilder private func dublettenZeile(_ id: Int) -> some View {
        if let vorhanden = store.weine.first(where: { $0.id == id }) {
            HStack(spacing: 10) {
                Label("Ähnlich: " + vorhanden.titel, systemImage: "doc.on.doc")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                NavigationLink {
                    WeinDetailView(wein: vorhanden).environmentObject(store)
                } label: {
                    Text("Ansehen").font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(tint)
                .accessibilityIdentifier("wein-dublette-ansehen")
            }
        } else {
            // Kann passieren, wenn die Liste noch nicht (neu) geladen ist — dann lieber sagen, dass
            // es einen Verdacht gibt, als gar nichts zu zeigen.
            Text("Ein ähnlicher Eintrag ist vermerkt, aber gerade nicht geladen.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // ── Bewertungen ──

    private var bewertungsblock: some View {
        block("Bewertungen") {
            VStack(alignment: .leading, spacing: 12) {
                if let s = store.schnitt(current) {
                    HStack(spacing: 6) {
                        Text("Schnitt").font(.subheadline).foregroundStyle(.secondary)
                        Text(WeinText.zahl(s) + " von 5").font(.subheadline.weight(.semibold))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Meine Bewertung").font(.subheadline.weight(.semibold))
                    WeinSterne(auswahl: $sterne, identifier: "wein-stern")
                    TextField("Kommentar (optional)", text: $kommentar, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("wein-kommentar")
                    if (store.owner ?? "").isEmpty {
                        Text("Ohne persönlichen Zugangsschlüssel lässt sich keine Bewertung zuordnen.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Button {
                        Task { await bewertungSpeichern() }
                    } label: {
                        if speichert {
                            HStack(spacing: 8) { ProgressView(); Text("Speichert …") }
                        } else {
                            Text(store.meine(current) == nil ? "Bewertung speichern" : "Bewertung aktualisieren")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .disabled(sterne < 1 || speichert)
                    .accessibilityIdentifier("wein-bewerten")
                }

                Divider()

                if let a = store.andere(current) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(WeinText.person(a.owner)).font(.subheadline.weight(.semibold))
                        WeinSterne(sterne: a.sterne, gross: true)
                        if !a.kommentar.isEmpty {
                            Text(a.kommentar).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Die andere Person hat " + diesesGetraenk + " noch nicht bewertet.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // ── Stammdaten ──

    /// Der Rahmen ist fuer beide Arten gleich (Hersteller, Alkohol, Serviertemperatur, Flasche,
    /// EAN); dazwischen steht der art-eigene Teil. Zeilen ohne Wert entfallen ganz — „Alter: —"
    /// waere eine Zeile, die nichts sagt.
    private var stammdaten: some View {
        block("Stammdaten") {
            VStack(spacing: 0) {
                if !current.weingut.isEmpty {
                    InfoRow(icon: current.art == .spirituose ? "🏭" : "🏛️",
                            label: current.art == .spirituose ? "Destillerie" : "Weingut",
                            value: current.weingut)
                }
                if current.art == .wein { weinStammdaten } else { spirituosenStammdaten }
                if let a = current.alkohol { InfoRow(icon: "🥃", label: "Alkohol", value: WeinText.alkohol(a)) }
                if let t = current.serviertemperatur, !t.isEmpty {
                    InfoRow(icon: "🌡️", label: "Serviertemperatur", value: t)
                }
                InfoRow(icon: "🍾", label: "Flasche", value: WeinText.flasche(current.flaschengroesseMl))
                if let e = current.ean, !e.isEmpty { InfoRow(icon: "🔖", label: "EAN", value: e) }
            }
        }
    }

    /// Jahrgang steht auch ohne Wert da ("o. J." = jahrgangslos, eine echte Aussage bei Sekt);
    /// Rebsorten nur, wenn welche erfasst sind.
    @ViewBuilder private var weinStammdaten: some View {
        InfoRow(icon: "📅", label: "Jahrgang", value: WeinText.jahrgang(current.jahrgang))
        if !current.rebsorten.isEmpty {
            InfoRow(icon: "🍇", label: "Rebsorten", value: current.rebsorten.joined(separator: ", "))
        }
        InfoRow(icon: "🍬", label: "Geschmack", value: WeinGeschmack.label(current.geschmacksrichtung))
    }

    /// Kein Jahrgang: was zwei Abfuellungen derselben Destillerie unterscheidet, sind Altersangabe
    /// und Abfuelljahr. Abfuellungen ohne Alter (NAS) sind normal — `WeinFormat.alterText` liefert
    /// dafuer nil und die Zeile entfaellt, statt "0 Jahre" zu behaupten.
    @ViewBuilder private var spirituosenStammdaten: some View {
        if let k = current.kategorie { InfoRow(icon: k.emoji, label: "Kategorie", value: k.label) }
        if let s = current.stil, !s.isEmpty { InfoRow(icon: "🏷️", label: "Stil", value: s) }
        if let alter = WeinFormat.alterText(current.alterJahre) {
            InfoRow(icon: "⏳", label: "Alter", value: alter)
        }
        if let f = current.fass, !f.isEmpty { InfoRow(icon: "🛢️", label: "Fass", value: f) }
        if let j = current.abgefuelltJahr, j > 0 {
            InfoRow(icon: "📅", label: "Abgefüllt", value: String(j))
        }
    }

    // ── Geschmacksprofil ──

    private var profilWerte: [WeinProfilEintrag] {
        var w: [WeinProfilEintrag] = []
        if let v = current.suesse { w.append(.init(id: "Süße", wert: v, farbe: Color(hex: "EC4899"))) }
        if let v = current.saeure { w.append(.init(id: "Säure", wert: v, farbe: Color(hex: "84CC16"))) }
        if let v = current.tannin { w.append(.init(id: "Tannin", wert: v, farbe: Color(hex: "92400E"))) }
        if let v = current.koerper { w.append(.init(id: "Körper", wert: v, farbe: Color(hex: "7C3AED"))) }
        return w
    }

    /// Nur beim Wein: Suesse/Saeure/Tannin/Koerper sind Weinspalten und werden fuer Spirituosen
    /// weder erfasst noch gespeichert (`patchFields` schickt sie dort gar nicht mit).
    @ViewBuilder private var geschmacksprofil: some View {
        if current.art == .wein, !profilWerte.isEmpty {
            block("Geschmacksprofil") {
                VStack(spacing: 8) {
                    ForEach(profilWerte) { e in
                        WeinProfilBalken(label: e.id, wert: e.wert, farbe: e.farbe)
                    }
                }
            }
        }
    }

    @ViewBuilder private var aromen: some View {
        if !current.aromen.isEmpty {
            block("Aromen") {
                FlowLayout(spacing: 6) {
                    ForEach(current.aromen, id: \.self) { a in
                        Pill(text: a, color: tint, filled: false)
                    }
                }
            }
        }
    }

    // ── Nur Spirituosen: Trinkempfehlung + Cocktails ──

    /// „pur", „on the rocks", „Gin Tonic mit Fever-Tree" — eine Zeile Fliesstext, kein Feldsalat.
    @ViewBuilder private var trinkempfehlung: some View {
        if current.art == .spirituose, let text = current.trinkempfehlung, !text.isEmpty {
            block("Trinkempfehlung") {
                Text(text).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Passende Drinks als Chips — gleiche Optik wie die Aromen, weil es dieselbe Art Liste ist.
    @ViewBuilder private var cocktails: some View {
        if current.art == .spirituose, !current.cocktails.isEmpty {
            block("Cocktails") {
                FlowLayout(spacing: 6) {
                    ForEach(current.cocktails, id: \.self) { c in
                        Pill(text: c, color: tint, filled: false)
                    }
                }
            }
        }
    }

    @ViewBuilder private var hintergrund: some View {
        if let text = current.beschreibung, !text.isEmpty {
            block("Hintergrund") {
                Text(text).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        if let speise = current.speiseempfehlung, !speise.isEmpty {
            NoteBlock(icon: "🍽️", text: speise, tint: Color(hex: "F59E0B"))
        }
    }

    @ViewBuilder private var auszeichnungen: some View {
        if !current.auszeichnungen.isEmpty {
            block("Auszeichnungen") {
                FlowLayout(spacing: 6) {
                    ForEach(current.auszeichnungen, id: \.self) { a in
                        Pill(text: a, systemImage: "rosette", color: Color(hex: "F59E0B"))
                    }
                }
            }
        }
    }

    /// Nur beim Wein: eine Spirituose reift in der Flasche nicht weiter, sie hat kein Trinkfenster.
    @ViewBuilder private var trinkfenster: some View {
        if current.art == .wein, current.trinkfensterVon != nil || current.trinkfensterBis != nil {
            block("Trinkfenster") {
                HStack(spacing: 8) {
                    Text(WeinText.trinkfenster(current.trinkfensterVon, current.trinkfensterBis))
                        .font(.subheadline.weight(.semibold))
                    if current.istTrinkreif {
                        Pill(text: "jetzt trinkreif", systemImage: "checkmark.seal.fill", color: Color(hex: "16A34A"))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // ── Keller ──

    private var kellerBlock: some View {
        block("Keller") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Text("Flaschen").font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button {
                        Task { await store.setBestand(current, max(0, current.bestand - 1)) }
                    } label: {
                        Image(systemName: "minus.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(current.bestand > 0 ? tint : Color.secondary.opacity(0.4))
                    .disabled(current.bestand == 0)
                    .accessibilityLabel("Eine Flasche weniger")
                    .accessibilityIdentifier("wein-bestand-minus")

                    Text(String(current.bestand)).font(.title3.weight(.bold)).frame(minWidth: 32)

                    Button {
                        Task { await store.setBestand(current, current.bestand + 1) }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(tint)
                    .accessibilityLabel("Eine Flasche mehr")
                    .accessibilityIdentifier("wein-bestand-plus")
                }
                if let ort = current.lagerort, !ort.isEmpty {
                    InfoRow(icon: "📦", label: "Lagerort", value: ort)
                }
                standortZeile
            }
        }
    }

    // ── Fuellstand (nur Spirituosen) ──

    /// Die Frage an der Bar ist nicht „wie viele Flaschen", sondern „wie viel ist noch drin".
    /// Deshalb hier ein Balken statt eines Zaehlers — und sechs feste Stufen statt eines
    /// Schiebereglers: niemand misst den Rest einer Flasche prozentgenau, und ein Tipp ist
    /// schneller als eine Ziehbewegung.
    /// Die Karte traegt den Zustand DIESER Flasche — Fuellstand und angebrochen.
    /// Der Standort-Umschalter stand frueher hier, weil nur Spirituosen geparkt wurden; jetzt gilt
    /// er fuer beide Arten und sitzt deshalb im Keller-Block, neben dem Lagerort: dort steht, WO
    /// die Flaschen liegen (Gebaeude und Regal), hier, wie viel noch drin ist.
    @ViewBuilder private var fuellstandBlock: some View {
        if current.art == .spirituose {
            block("Füllstand") {
                VStack(alignment: .leading, spacing: 12) {
                    fuellstandAnzeige
                    FlowLayout(spacing: 6) {
                        ForEach(Self.fuellstandStufen, id: \.self) { p in
                            FilterPill(label: Self.stufenText(p),
                                       selected: current.fuellstandProzent == p,
                                       color: tint) {
                                Task { await store.setFuellstand(current, p) }
                            }
                            .accessibilityIdentifier("wein-fuellstand-" + String(p))
                        }
                    }
                    angebrochenZeile
                }
            }
        }
    }

    /// Ohne erfassten Wert wird KEIN Balken gezeigt: einer auf 0 % saehe aus wie eine leere
    /// Flasche, obwohl der Wert schlicht fehlt.
    @ViewBuilder private var fuellstandAnzeige: some View {
        if let p = current.fuellstandProzent {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(current.fuellstandLabel ?? Self.stufenText(p)).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Text(String(p) + " %").font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(min(100, max(0, p))), total: 100)
                    .progressViewStyle(.linear)
                    .tint(tint)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Füllstand " + String(p) + " Prozent")
            .accessibilityIdentifier("wein-fuellstand")
        } else {
            Text("Füllstand noch nicht erfasst.")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("wein-fuellstand")
        }
    }

    /// Angebrochen ist eine eigene Aussage: eine volle, aber geoeffnete Flasche altert anders als
    /// eine ungeoeffnete. Der Store setzt beim Oeffnen zusaetzlich den Fuellstand auf 100, wenn
    /// noch keiner erfasst war — deshalb steht hier nur der Schalter, keine Rechnerei.
    private var angebrochenZeile: some View {
        // Beide Beschriftungen vorab als String — ein Ternaer aus zwei Literalen direkt im
        // `Button(...)` liesse dem Compiler die Wahl zwischen LocalizedStringKey und String.
        let offen = current.istAngebrochen
        let seit = WeinText.datum(current.angebrochenAt)
        let stand: String = offen ? (seit.isEmpty ? "angebrochen" : "angebrochen seit " + seit) : "ungeöffnet"
        let knopf: String = offen ? "Als ungeöffnet markieren" : "Flasche öffnen"
        return HStack(spacing: 10) {
            Label(stand, systemImage: offen ? "drop.fill" : "seal")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(knopf) {
                Task { await store.setAngebrochen(current, !offen) }
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .tint(tint)
            .accessibilityIdentifier("wein-angebrochen")
        }
    }

    /// Wo die Flasche steht — Gebaeude, nicht Regal: der `lagerort` direkt darueber bleibt daneben
    /// gueltig („im Buero, dort im Schrank links"). Geparkt heisst NICHT weg: der Bestand bleibt
    /// unangetastet, es kommt nur das Label dazu, damit zu Hause niemand danach sucht.
    /// Gilt fuer BEIDE Getraenkearten: eine Weinkiste im Buero ist genauso wenig zu Hause wie die
    /// Ginflasche, und ein Abzeichen ohne Bedienelement (so war es vorher beim Wein) ist schlimmer
    /// als eins zu viel.
    /// Aufbau wie `angebrochenZeile` — beide Beschriftungen vorab als String, weil ein Ternaer aus
    /// zwei Literalen direkt im `Button(...)` dem Compiler die Wahl zwischen LocalizedStringKey und
    /// String liesse.
    private var standortZeile: some View {
        let hier = current.standort
        let ziel: WeinStandort = hier == .buero ? .zuhause : .buero
        let knopf: String = ziel == .buero ? "Im Büro parken" : "Wieder zu Hause"
        return HStack(spacing: 10) {
            Label(hier.label, systemImage: hier.symbol)
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(knopf) {
                Task { await store.setStandort(current, ziel) }
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .tint(tint)
            .accessibilityIdentifier("wein-standort-toggle")
        }
    }

    /// Die sechs Stufen des Balkens — dieselben Werte, aus denen `Wein.fuellstandLabel` seine
    /// Beschriftung ableitet.
    private static let fuellstandStufen = [100, 75, 50, 25, 10, 0]

    /// Beschriftung einer Stufe, wortgleich zu `Wein.fuellstandLabel` — Knopf und Anzeige duerfen
    /// nicht verschiedene Woerter fuer denselben Zustand benutzen.
    private static func stufenText(_ prozent: Int) -> String {
        switch prozent {
        case 100: return "voll"
        case 75:  return "¾ voll"
        case 50:  return "halb"
        case 25:  return "¼"
        case 10:  return "Neige"
        default:  return "leer"
        }
    }

    // ── Preise ──

    private var preisBlock: some View {
        block("Preise") {
            VStack(alignment: .leading, spacing: 10) {
                if let ref = current.referenzpreis {
                    InfoRow(icon: "🏷️", label: "Referenzpreis", value: WeinText.eur(ref))
                }
                if let best = current.besterPreis {
                    InfoRow(icon: "💶", label: "Bester Preis", value: WeinText.eur(best),
                            valueColor: Color(hex: "16A34A"))
                    if let r = current.rabattProzent, r >= 5 {
                        HStack {
                            Pill(text: WeinText.rabatt(r) + " gegenüber Referenz", systemImage: "tag.fill",
                                 color: Color(hex: "16A34A"))
                            Spacer(minLength: 0)
                        }
                    }
                }
                haendlerZeile
                let geprueft = WeinText.datum(current.preisGeprueftAt)
                InfoRow(icon: "🕒", label: "Zuletzt geprüft", value: geprueft.isEmpty ? "noch nie" : geprueft)

                Toggle(isOn: Binding(get: { current.preisBeobachten },
                                     set: { neu in Task { await store.setBeobachten(current, neu) } })) {
                    Text("Preis beobachten").font(.subheadline)
                }
                .tint(tint)
                .accessibilityIdentifier("wein-beobachten")

                Button {
                    Task { await preisPruefen() }
                } label: {
                    if pruefe {
                        HStack(spacing: 8) { ProgressView(); Text("Sucht Angebote …") }
                    } else {
                        Label("Preis jetzt prüfen", systemImage: "magnifyingglass")
                    }
                }
                .buttonStyle(.bordered)
                .tint(tint)
                .disabled(pruefe)
                .accessibilityIdentifier("wein-preischeck")

                preisverlauf
            }
        }
    }

    @ViewBuilder private var haendlerZeile: some View {
        let haendler = current.besterPreisHaendler ?? ""
        if let link = current.besterPreisURL, let url = URL(string: link) {
            Link(destination: url) {
                Label(haendler.isEmpty ? "Zum Angebot" : haendler, systemImage: "arrow.up.right.square")
                    .font(.subheadline)
            }
            .accessibilityIdentifier("wein-preis-link")
        } else if !haendler.isEmpty {
            InfoRow(icon: "🏬", label: "Händler", value: haendler)
        }
    }

    @ViewBuilder private var preisverlauf: some View {
        if !preise.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Preisverlauf").font(.caption.weight(.bold)).foregroundStyle(.secondary).padding(.top, 4)
                ForEach(preise) { p in
                    HStack(spacing: 8) {
                        Text(WeinText.datum(p.gefundenAt)).font(.caption2).foregroundStyle(.secondary)
                            .frame(width: 74, alignment: .leading)
                        if let url = p.linkURL {
                            Link(p.haendler.isEmpty ? "Angebot" : p.haendler, destination: url)
                                .font(.caption).lineLimit(1)
                        } else {
                            Text(p.haendler.isEmpty ? "unbekannt" : p.haendler)
                                .font(.caption).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text(WeinText.eur(p.preis)).font(.caption.weight(.semibold))
                    }
                }
            }
        }
    }

    @ViewBuilder private var notizen: some View {
        if let n = current.notizen, !n.isEmpty {
            NoteBlock(icon: "📝", text: n)
        }
    }
}

// MARK: - Geschmacksprofil-Balken

/// Ein Wert des Geschmacksprofils. Eigener Typ statt Tupel, weil `ForEach` einen Schluesselpfad
/// braucht und Tupel-Bestandteile keinen haben.
struct WeinProfilEintrag: Identifiable {
    /// Beschriftung (Süße/Säure/Tannin/Körper) — je Wein eindeutig, taugt daher als Id.
    let id: String
    let wert: Int
    let farbe: Color
}

/// Ein Profilwert (1 bis 5) als fuenf Segmente — ohne GeometryReader, damit es in jeder
/// Breite und in der Vorschau stabil bleibt.
struct WeinProfilBalken: View {
    let label: String
    let wert: Int
    let farbe: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { i in
                    Capsule()
                        .fill(i <= wert ? farbe : Color.secondary.opacity(0.18))
                        .frame(height: 8)
                }
            }
            Text(String(max(0, min(5, wert))) + "/5").font(.caption2).foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label + " " + String(wert) + " von 5")
    }
}
