import SwiftUI
import UIKit

/// Schritt 2 der Wein-Erfassung: alles, was die KI ermittelt hat, wird sichtbar und ist editierbar —
/// gegliedert in Wein / Herkunft / Geschmack / Hintergrund / Preis / Keller. Vertrauensgrad, Hinweise
/// und die Quellen-Links stehen oben. Erst der Speichern-Knopf legt den Datensatz an (Etikettenfoto zuerst
/// hochladen, damit der Wein gleich mit `foto_key` entsteht), danach kann direkt die eigene
/// Sterne-Bewertung gesetzt werden.
///
/// Meldet das Backend eine Dublette, steht ganz oben eine Karte mit den vorhandenen Bewertungen und
/// zwei Wegen: vorhandenen Wein öffnen oder trotzdem als eigenen Eintrag anlegen (anderer Jahrgang).
///
/// Wird von `WeinErfassenView` gepusht und lebt in dessen NavigationStack — hier KEIN eigener Stack.
struct WeinPruefenView: View {
    let vorschlag: WeinVorschlag
    /// Etikettenfoto aus Schritt 1 (wird beim Speichern hochgeladen).
    var foto: UIImage? = nil
    /// Nach dem Anlegen mit der neuen Wein-ID gerufen.
    var onGespeichert: (Int) -> Void = { _ in }
    /// Vorhandenen Wein aus der Dubletten-Karte öffnen.
    var onDubletteOeffnen: (Int) -> Void = { _ in }
    /// Schließt den gesamten Erfassungs-Flow (nicht nur diesen Bildschirm).
    var schliessen: () -> Void = {}

    @EnvironmentObject private var store: WeinStore

    // ── Wein ──
    @State private var name = ""
    @State private var weingut = ""
    @State private var jahrgang = ""
    @State private var typ: WeinTyp = .rot
    @State private var rebsorten: [String] = []
    @State private var flaschengroesse = "750"
    @State private var ean = ""
    // ── Herkunft ──
    @State private var land = ""
    @State private var region = ""
    @State private var lage = ""
    // ── Geschmack ──
    @State private var geschmacksrichtung = "unbekannt"
    @State private var alkohol = ""
    @State private var suesse: Int?
    @State private var saeure: Int?
    @State private var tannin: Int?
    @State private var koerper: Int?
    @State private var aromen: [String] = []
    @State private var serviertemperatur = ""
    @State private var trinkfensterVon = ""
    @State private var trinkfensterBis = ""
    @State private var bio = false
    @State private var vegan = false
    // ── Hintergrund ──
    @State private var beschreibung = ""
    @State private var auszeichnungen: [String] = []
    @State private var speiseempfehlung = ""
    @State private var notizen = ""
    // ── Preis ──
    @State private var referenzpreis = ""
    @State private var besterPreis = ""
    @State private var besterHaendler = ""
    @State private var besterURL = ""
    @State private var gekauftPreis = ""
    @State private var gekauftBei = ""
    @State private var beobachten = true
    // ── Keller ──
    @State private var bestand = 1
    @State private var lagerort = ""

    // ── Ablauf ──
    @State private var quelle = "ki"
    @State private var vorbefuellt = false
    @State private var speichert = false
    @State private var fehler = ""
    @State private var dubletteWeggeklickt = false
    @State private var gespeicherteId: Int?
    /// Der Feldstand, der zuletzt wirklich beim Server angekommen ist. Alles, was danach im
    /// Formular getippt wird, gilt als offene Korrektur. NSDictionary, weil `[String: Any]`
    /// nicht Equatable ist.
    @State private var gespeicherterStand: NSDictionary?
    @State private var sterne = 0
    @State private var kommentar = ""
    @State private var bewertet = false

    /// Erlaubte Werte der Spalte `geschmacksrichtung` (CHECK) mit deutschem Etikett.
    private static let geschmacksrichtungen: [WeinGeschmacksrichtung] = [
        WeinGeschmacksrichtung(id: "trocken", label: "Trocken"),
        WeinGeschmacksrichtung(id: "halbtrocken", label: "Halbtrocken"),
        WeinGeschmacksrichtung(id: "feinherb", label: "Feinherb"),
        WeinGeschmacksrichtung(id: "lieblich", label: "Lieblich"),
        WeinGeschmacksrichtung(id: "suess", label: "Süß"),
        WeinGeschmacksrichtung(id: "brut nature", label: "Brut Nature"),
        WeinGeschmacksrichtung(id: "extra brut", label: "Extra Brut"),
        WeinGeschmacksrichtung(id: "brut", label: "Brut"),
        WeinGeschmacksrichtung(id: "extra dry", label: "Extra Dry"),
        WeinGeschmacksrichtung(id: "sec", label: "Sec"),
        WeinGeschmacksrichtung(id: "demi-sec", label: "Demi-Sec"),
        WeinGeschmacksrichtung(id: "unbekannt", label: "Unbekannt"),
    ]

    var body: some View {
        Form {
            kopf
            weinSection
            herkunftSection
            geschmackSection
            hintergrundSection
            preisSection
            kellerSection
            abschluss
        }
        .navigationTitle("Prüfen und speichern")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: vorbefuellen)
    }

    // MARK: - Kopf: Dublette + Vertrauensgrad

    @ViewBuilder private var kopf: some View {
        if let d = vorschlag.dublette, !dubletteWeggeklickt, gespeicherteId == nil {
            dubletteSection(d)
        }
        vertrauenSection
    }

    private func dubletteSection(_ d: WeinDublette) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(d.titel).font(.subheadline.weight(.semibold))
                if d.bewertungen.isEmpty {
                    Text("Noch von niemandem bewertet.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(d.bewertungen) { b in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(person(b.owner))
                                .font(.caption.weight(.semibold))
                                .frame(width: 46, alignment: .leading)
                            WeinSterneAnzeige(sterne: b.sterne)
                            if !b.kommentar.isEmpty {
                                Text(b.kommentar).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                HStack(spacing: 10) {
                    Button { onDubletteOeffnen(d.id) } label: {
                        Label("Wein öffnen", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("wein-pruefen-dublette-oeffnen")

                    Button("Trotzdem neu anlegen") { dubletteWeggeklickt = true }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("wein-pruefen-dublette-trotzdem")
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
            }
            .padding(.vertical, 4)
        } header: {
            Label("Kennt ihr schon", systemImage: "sparkle.magnifyingglass")
        } footer: {
            Text("Anderer Jahrgang oder eine zweite Flasche? Dann trotzdem als eigenen Eintrag anlegen.")
        }
    }

    private var vertrauenSection: some View {
        Section {
            HStack(spacing: 10) {
                Pill(text: vertrauenLabel, systemImage: "sparkles", color: vertrauenFarbe)
                Text("Alle Angaben sind Vorschläge. Bitte prüfen und ergänzen.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            ForEach(Array(vorschlag.hinweise.enumerated()), id: \.offset) { _, h in
                NoteBlock(icon: "ℹ️", text: h, tint: .blue)
            }
            ForEach(Array(vorschlag.quellen.enumerated()), id: \.offset) { i, q in
                if let url = URL(string: q) {
                    Link(destination: url) {
                        HStack(spacing: 8) {
                            Image(systemName: "link").foregroundStyle(.secondary)
                            Text(kurz(q)).lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                    .accessibilityIdentifier("wein-pruefen-quelle-" + String(i))
                }
            }
        } header: {
            Text("KI-Analyse")
        }
    }

    // MARK: - Wein

    private var weinSection: some View {
        Section {
            TextField("Weingut", text: $weingut)
                .accessibilityIdentifier("wein-pruefen-weingut")
            TextField("Name des Weins", text: $name)
                .accessibilityIdentifier("wein-pruefen-name")
            TextField("Jahrgang (leer = jahrgangslos)", text: $jahrgang)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("wein-pruefen-jahrgang")
            Picker("Art", selection: $typ) {
                ForEach(WeinTyp.allCases) { t in
                    Text(t.emoji + " " + t.label).tag(t)
                }
            }
            .accessibilityIdentifier("wein-pruefen-typ")
            VStack(alignment: .leading, spacing: 6) {
                Text("Rebsorten").font(.caption).foregroundStyle(.secondary)
                WeinTagFeld(platzhalter: "Rebsorte hinzufügen", tags: $rebsorten,
                            kennung: "wein-pruefen-rebsorten", farbe: akzent)
            }
            TextField("Flaschengröße in ml", text: $flaschengroesse)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("wein-pruefen-flaschengroesse")
            TextField("EAN", text: $ean)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("wein-pruefen-ean")
            if let img = foto {
                HStack(spacing: 12) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text("Etikettenfoto wird mitgespeichert.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        } header: {
            Text("Wein")
        }
    }

    // MARK: - Herkunft

    private var herkunftSection: some View {
        Section {
            TextField("Land", text: $land)
                .accessibilityIdentifier("wein-pruefen-land")
            TextField("Region", text: $region)
                .accessibilityIdentifier("wein-pruefen-region")
            TextField("Lage / Weinberg", text: $lage)
                .accessibilityIdentifier("wein-pruefen-lage")
        } header: {
            Text("Herkunft")
        }
    }

    // MARK: - Geschmack

    private var geschmackSection: some View {
        Section {
            Picker("Geschmacksrichtung", selection: $geschmacksrichtung) {
                ForEach(Self.geschmacksrichtungen) { g in
                    Text(g.label).tag(g.id)
                }
            }
            .accessibilityIdentifier("wein-pruefen-geschmacksrichtung")

            TextField("Alkohol in Volumenprozent", text: $alkohol)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("wein-pruefen-alkohol")

            VStack(alignment: .leading, spacing: 14) {
                WeinProfilRegler(titel: "Süße", links: "trocken", rechts: "süß",
                                 wert: $suesse, kennung: "wein-pruefen-suesse")
                WeinProfilRegler(titel: "Säure", links: "mild", rechts: "frisch",
                                 wert: $saeure, kennung: "wein-pruefen-saeure")
                WeinProfilRegler(titel: "Tannin", links: "weich", rechts: "kräftig",
                                 wert: $tannin, kennung: "wein-pruefen-tannin")
                WeinProfilRegler(titel: "Körper", links: "leicht", rechts: "voll",
                                 wert: $koerper, kennung: "wein-pruefen-koerper")
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Aromen").font(.caption).foregroundStyle(.secondary)
                WeinTagFeld(platzhalter: "Aroma hinzufügen", tags: $aromen,
                            kennung: "wein-pruefen-aromen", farbe: akzent)
            }

            TextField("Serviertemperatur (z. B. 16-18 °C)", text: $serviertemperatur)
                .accessibilityIdentifier("wein-pruefen-serviertemperatur")

            HStack(spacing: 12) {
                Text("Trinkfenster").foregroundStyle(.secondary)
                Spacer(minLength: 8)
                TextField("von", text: $trinkfensterVon)
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 62)
                    .accessibilityIdentifier("wein-pruefen-trinkfenster-von")
                Text("bis").foregroundStyle(.secondary)
                TextField("bis", text: $trinkfensterBis)
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 62)
                    .accessibilityIdentifier("wein-pruefen-trinkfenster-bis")
            }

            Toggle("Bio", isOn: $bio)
                .accessibilityIdentifier("wein-pruefen-bio")
            Toggle("Vegan", isOn: $vegan)
                .accessibilityIdentifier("wein-pruefen-vegan")
        } header: {
            Text("Geschmack")
        } footer: {
            Text("Die Regler sind 1 bis 5. Ganz links heißt: keine Angabe.")
        }
    }

    // MARK: - Hintergrund

    private var hintergrundSection: some View {
        Section {
            TextField("Beschreibung (Weingut, Lage, Ausbau)", text: $beschreibung, axis: .vertical)
                .lineLimit(3...10)
                .accessibilityIdentifier("wein-pruefen-beschreibung")
            VStack(alignment: .leading, spacing: 6) {
                Text("Auszeichnungen").font(.caption).foregroundStyle(.secondary)
                WeinTagFeld(platzhalter: "z. B. Falstaff 93", tags: $auszeichnungen,
                            kennung: "wein-pruefen-auszeichnungen", farbe: .orange)
            }
            TextField("Passt zu (Speiseempfehlung)", text: $speiseempfehlung, axis: .vertical)
                .lineLimit(1...4)
                .accessibilityIdentifier("wein-pruefen-speiseempfehlung")
            TextField("Eigene Notizen", text: $notizen, axis: .vertical)
                .lineLimit(1...4)
                .accessibilityIdentifier("wein-pruefen-notizen")
        } header: {
            Text("Hintergrund")
        }
    }

    // MARK: - Preis

    private var preisSection: some View {
        Section {
            if vorschlag.preise.isEmpty {
                Text(keinePreiseText)
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("wein-pruefen-keine-preise")
            } else {
                ForEach(Array(vorschlag.preise.enumerated()), id: \.offset) { i, t in
                    Button { uebernehmen(t) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.haendler.isEmpty ? "Unbekannter Händler" : t.haendler)
                                    .font(.subheadline)
                                if let u = t.url, !u.isEmpty {
                                    Text(kurz(u)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 8)
                            Text(euro(t.preis)).font(.subheadline.weight(.semibold))
                            Image(systemName: istUebernommen(t) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(istUebernommen(t) ? Color.green : Color.secondary.opacity(0.4))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wein-pruefen-angebot-" + String(i))
                }
            }

            TextField("Referenzpreis in Euro", text: $referenzpreis)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("wein-pruefen-referenzpreis")
            TextField("Bester gefundener Preis", text: $besterPreis)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("wein-pruefen-bester-preis")
            TextField("Händler", text: $besterHaendler)
                .accessibilityIdentifier("wein-pruefen-bester-haendler")
            TextField("Link zum Angebot", text: $besterURL)
                .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                .accessibilityIdentifier("wein-pruefen-bester-url")
            TextField("Selbst bezahlt", text: $gekauftPreis)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("wein-pruefen-gekauft-preis")
            TextField("Gekauft bei", text: $gekauftBei)
                .accessibilityIdentifier("wein-pruefen-gekauft-bei")
            Toggle("Preis beobachten", isOn: $beobachten)
                .accessibilityIdentifier("wein-pruefen-beobachten")
        } header: {
            Text("Preis")
        } footer: {
            Text("Der Referenzpreis ist die Basis für die Rabattrechnung. Ein Angebot antippen übernimmt es als besten Preis.")
        }
    }

    // MARK: - Keller

    private var kellerSection: some View {
        Section {
            Stepper(value: $bestand, in: 0...999) {
                HStack {
                    Text("Flaschen im Keller")
                    Spacer(minLength: 8)
                    Text(String(bestand)).foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("wein-pruefen-bestand")
            TextField("Lagerort (z. B. Regal unten links)", text: $lagerort)
                .accessibilityIdentifier("wein-pruefen-lagerort")
        } header: {
            Text("Keller")
        }
    }

    // MARK: - Speichern + eigene Bewertung

    @ViewBuilder private var abschluss: some View {
        if !fehler.isEmpty {
            Section { Text(fehler).font(.footnote).foregroundStyle(.red) }
        }
        Section {
            Button { Task { await speichern() } } label: {
                HStack(spacing: 8) {
                    if speichert { ProgressView() }
                    Text(speichernTitel)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            // Nach dem Anlegen bleibt der Knopf nutzbar: die Felder sind weiter editierbar, also
            // muss eine Korrektur auch noch abschickbar sein (dann als PATCH auf den Wein).
            .disabled(speichert
                      || name.trimmingCharacters(in: .whitespaces).isEmpty
                      || (gespeicherteId != nil && !geaendert))
            .accessibilityIdentifier("wein-pruefen-speichern")
        } footer: {
            if gespeicherteId == nil {
                Text("Ein Name genügt zum Speichern. Alles andere lässt sich später ergänzen.")
            } else if geaendert {
                Text("Es gibt noch nicht gespeicherte Änderungen.")
            }
        }
        if gespeicherteId != nil { bewertungSection }
    }

    private var bewertungSection: some View {
        Section {
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { i in
                    Button { sterne = (sterne == i) ? 0 : i } label: {
                        Image(systemName: sterne >= i ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundStyle(sterne >= i ? Color.yellow : Color.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(i) + " von 5 Sternen")
                    .accessibilityIdentifier("wein-pruefen-stern-" + String(i))
                }
                Spacer(minLength: 0)
            }
            TextField("Kommentar (optional)", text: $kommentar, axis: .vertical)
                .lineLimit(1...3)
                .accessibilityIdentifier("wein-pruefen-bewertung-kommentar")
            Button(bewertet ? "Bewertung gespeichert" : "Bewertung speichern") {
                Task { await bewerten() }
            }
            .disabled(sterne == 0 || bewertet)
            .accessibilityIdentifier("wein-pruefen-bewertung-speichern")
            Button("Fertig") {
                Task {
                    // Offene Korrektur zuerst abschicken, damit sie beim Verlassen nicht still
                    // verloren geht. Kam sie nicht durch, bleibt der Bildschirm mit der
                    // Fehlermeldung stehen statt die Eingabe wegzuwerfen.
                    if gespeicherteId != nil, geaendert {
                        let angekommen = await speichern()
                        if !angekommen { return }
                    }
                    schliessen()
                }
            }
            .disabled(speichert)
            .accessibilityIdentifier("wein-pruefen-fertig")
        } header: {
            Text("Deine Bewertung")
        } footer: {
            Text("Optional. Du kannst den Wein auch später bewerten.")
        }
    }

    // MARK: - Vorbefüllen

    private func vorbefuellen() {
        guard !vorbefuellt else { return }
        vorbefuellt = true
        let f = vorschlag.felder

        name = Coerce.str(f["name"]) ?? ""
        weingut = Coerce.str(f["weingut"]) ?? ""
        if let j = Coerce.int(f["jahrgang"]) { jahrgang = String(j) }
        typ = WeinTyp(rawValue: Coerce.str(f["typ"]) ?? "") ?? .rot
        rebsorten = Coerce.stringArray(f["rebsorten"])
        if let g = Coerce.int(f["flaschengroesse_ml"]) { flaschengroesse = String(g) }
        ean = Coerce.str(f["ean"]) ?? ""

        land = Coerce.str(f["land"]) ?? ""
        region = Coerce.str(f["region"]) ?? ""
        lage = Coerce.str(f["lage"]) ?? ""

        let gr = Coerce.str(f["geschmacksrichtung"]) ?? "unbekannt"
        geschmacksrichtung = Self.geschmacksrichtungen.contains { $0.id == gr } ? gr : "unbekannt"
        if let a = Coerce.double(f["alkohol"]) { alkohol = zahl(a) }
        suesse = profil(f["suesse"])
        saeure = profil(f["saeure"])
        tannin = profil(f["tannin"])
        koerper = profil(f["koerper"])
        aromen = Coerce.stringArray(f["aromen"])
        serviertemperatur = Coerce.str(f["serviertemperatur"]) ?? ""
        if let v = Coerce.int(f["trinkfenster_von"]) { trinkfensterVon = String(v) }
        if let b = Coerce.int(f["trinkfenster_bis"]) { trinkfensterBis = String(b) }
        bio = Coerce.bool(f["bio"])
        vegan = Coerce.bool(f["vegan"])

        beschreibung = Coerce.str(f["beschreibung"]) ?? ""
        auszeichnungen = Coerce.stringArray(f["auszeichnungen"])
        speiseempfehlung = Coerce.str(f["speiseempfehlung"]) ?? ""
        notizen = Coerce.str(f["notizen"]) ?? ""

        if let r = Coerce.double(f["referenzpreis"]) { referenzpreis = zahl(r) }
        if let b = Coerce.double(f["bester_preis"]) {
            besterPreis = zahl(b)
            besterHaendler = Coerce.str(f["bester_preis_haendler"]) ?? ""
            besterURL = Coerce.str(f["bester_preis_url"]) ?? ""
        } else if let g = guenstigstes {
            besterPreis = zahl(g.preis)
            besterHaendler = g.haendler
            besterURL = g.url ?? ""
        }
        // Ohne Referenzpreis gäbe es keine Rabattbasis: dann das teuerste gefundene Angebot nehmen
        // (das ist typischerweise der normale Ladenpreis).
        if referenzpreis.isEmpty, let t = teuerstes { referenzpreis = zahl(t.preis) }
        if let p = Coerce.double(f["gekauft_preis"]) { gekauftPreis = zahl(p) }
        gekauftBei = Coerce.str(f["gekauft_bei"]) ?? ""
        beobachten = f["preis_beobachten"] == nil ? true : Coerce.bool(f["preis_beobachten"])

        if let b = Coerce.int(f["bestand"]) { bestand = max(0, b) }
        lagerort = Coerce.str(f["lagerort"]) ?? ""
        quelle = Coerce.str(f["quelle"]) ?? "ki"
    }

    /// Geschmacksprofil-Wert nur übernehmen, wenn er im gültigen Bereich 1 bis 5 liegt.
    private func profil(_ v: Any?) -> Int? {
        guard let i = Coerce.int(v), (1...5).contains(i) else { return nil }
        return i
    }

    // MARK: - Speichern

    /// Legt den Wein an (erster Aufruf) oder schickt Korrekturen als PATCH nach.
    /// Rueckgabe: kam der Stand beim Server an?
    @discardableResult
    private func speichern() async -> Bool {
        speichert = true
        fehler = ""
        let neu = gespeicherteId == nil
        // Genau der Stand, der gleich rausgeht — als Vergleichsbasis fuer spaetere Korrekturen.
        // (Wer waehrend des Speicherns weitertippt, hat danach korrekt wieder eine offene Änderung.)
        let stand = patchFelder()
        var felder = stand
        // Foto ZUERST hochladen, damit der Wein direkt mit `foto_key` angelegt wird. Schlägt der
        // Upload fehl, wird der Wein trotzdem gespeichert (das Bild ist die Kür, nicht die Pflicht).
        // Nur beim Anlegen: ein Korrektur-PATCH wuerde dasselbe Etikett sonst erneut ablegen.
        if neu, let img = foto, let jpeg = img.jpegForUpload() {
            if let key = try? await store.api.uploadFoto(jpeg: jpeg) {
                felder["foto_key"] = key
            }
        }
        let id = await store.save(felder, id: gespeicherteId)
        if let id {
            gespeicherteId = id
            gespeicherterStand = stand as NSDictionary
            // Nur das Anlegen ist fuer den Aufrufer neu; der PATCH hat den Store bereits aktualisiert.
            if neu { onGespeichert(id) }
        } else {
            fehler = neu
                ? "Der Wein konnte nicht gespeichert werden. Bitte noch einmal versuchen."
                : "Die Änderungen konnten nicht gespeichert werden. Bitte noch einmal versuchen."
        }
        speichert = false
        return id != nil
    }

    /// Beschriftung des Speichern-Knopfs: anlegen → gespeichert → offene Korrektur.
    private var speichernTitel: String {
        if gespeicherteId == nil { return "Speichern" }
        return geaendert ? "Änderungen speichern" : "Gespeichert"
    }

    /// Weicht das Formular vom zuletzt gespeicherten Stand ab? Vor dem ersten Speichern immer true.
    private var geaendert: Bool {
        guard let stand = gespeicherterStand else { return true }
        return !stand.isEqual(patchFelder() as NSDictionary)
    }

    /// Felder in DB-Schreibweise. Leere Eingaben werden weggelassen (NULL statt Leerstring),
    /// Listen gehen als JSON-Text raus.
    private func patchFelder() -> [String: Any] {
        var f: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespaces),
            "weingut": weingut.trimmingCharacters(in: .whitespaces),
            "typ": typ.rawValue,
            "rebsorten": jsonText(rebsorten),
            "aromen": jsonText(aromen),
            "auszeichnungen": jsonText(auszeichnungen),
            "geschmacksrichtung": geschmacksrichtung,
            "bio": bio ? 1 : 0,
            "vegan": vegan ? 1 : 0,
            "flaschengroesse_ml": Int(flaschengroesse.trimmingCharacters(in: .whitespaces)) ?? 750,
            "preis_beobachten": beobachten ? 1 : 0,
            "bestand": bestand,
            "quelle": quelleSicher,
        ]
        if let j = Int(jahrgang.trimmingCharacters(in: .whitespaces)) { f["jahrgang"] = j }
        if let a = Coerce.double(alkohol) { f["alkohol"] = a }
        if let s = suesse { f["suesse"] = s }
        if let s = saeure { f["saeure"] = s }
        if let t = tannin { f["tannin"] = t }
        if let k = koerper { f["koerper"] = k }
        if let v = Int(trinkfensterVon.trimmingCharacters(in: .whitespaces)) { f["trinkfenster_von"] = v }
        if let b = Int(trinkfensterBis.trimmingCharacters(in: .whitespaces)) { f["trinkfenster_bis"] = b }
        if let r = Coerce.double(referenzpreis) { f["referenzpreis"] = r }
        if let b = Coerce.double(besterPreis) { f["bester_preis"] = b }
        if let p = Coerce.double(gekauftPreis) { f["gekauft_preis"] = p }
        for (spalte, wert) in [
            ("land", land), ("region", region), ("lage", lage),
            ("serviertemperatur", serviertemperatur), ("ean", ean),
            ("beschreibung", beschreibung), ("speiseempfehlung", speiseempfehlung),
            ("bester_preis_haendler", besterHaendler), ("bester_preis_url", besterURL),
            ("gekauft_bei", gekauftBei), ("lagerort", lagerort), ("notizen", notizen),
        ] {
            let t = wert.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { f[spalte] = t }
        }
        // Selbsteinschaetzung der KI mitschreiben, sonst bleibt `ki_confidence` dauerhaft NULL.
        // Bewusst aus `vorschlag.felder` und NICHT aus `vorschlag.confidence`: der manuelle Weg
        // setzt dort hart "niedrig", legt aber kein `ki_confidence` an — manuell erfasste Weine
        // bleiben so korrekt ohne KI-Stempel.
        if let c = Coerce.str(vorschlag.felder["ki_confidence"]),
           ["hoch", "mittel", "niedrig"].contains(c) {
            f["ki_confidence"] = c
        }
        return f
    }

    private func bewerten() async {
        guard let id = gespeicherteId, sterne > 0 else { return }
        var f = patchFelder()
        f["id"] = id
        let wein = store.weine.first { $0.id == id } ?? Wein(fields: f)
        // Erfolg erst nach Verifikation: `store.bewerten` meldet Fehler nur ueber den Bereichs-Toast,
        // und der liegt hinter diesem Sheet — hier also unsichtbar. Der Rueckgabewert sagt, ob der
        // SERVER die Bewertung angenommen hat. Aus `store.bewertungen` liesse sich das nicht sicher
        // ablesen: eine unveraendert wiederholte Bewertung sieht dort aus wie eine abgelehnte.
        // Bleibt sie aus (z. B. 400 no_owner bei geteiltem Schluessel), bleibt der Knopf aktiv und
        // der Grund steht im Formular.
        let angekommen = await store.bewerten(
            wein, sterne: sterne,
            kommentar: kommentar.trimmingCharacters(in: .whitespacesAndNewlines))
        bewertet = angekommen
        fehler = angekommen ? "" : "Die Bewertung konnte nicht gespeichert werden. Bitte noch einmal versuchen."
    }

    // MARK: - Kleinkram

    private var akzent: Color { Palette.colors(for: "wein").first ?? Theme.accent }

    private var vertrauenLabel: String {
        switch vorschlag.confidence {
        case "hoch": return "Vertrauen hoch"
        case "mittel": return "Vertrauen mittel"
        case "niedrig": return "Vertrauen niedrig"
        default: return "Vertrauen unbekannt"
        }
    }

    private var vertrauenFarbe: Color {
        switch vorschlag.confidence {
        case "hoch": return .green
        case "mittel": return .orange
        case "niedrig": return .red
        default: return .gray
        }
    }

    /// Ohne Perplexity-Key liefert das Backend keine Angebote, sondern einen Klartext-Hinweis —
    /// der muss hier stehen statt einer leeren Preiszeile.
    private var keinePreiseText: String {
        vorschlag.hinweise.isEmpty
            ? "Keine Angebote gefunden. Referenzpreis bitte selbst eintragen."
            : vorschlag.hinweise.joined(separator: " ")
    }

    private var guenstigstes: WeinPreisTreffer? { vorschlag.preise.min { $0.preis < $1.preis } }
    private var teuerstes: WeinPreisTreffer? { vorschlag.preise.max { $0.preis < $1.preis } }

    private var quelleSicher: String {
        ["manuell", "foto", "ean", "ki"].contains(quelle) ? quelle : "manuell"
    }

    private func uebernehmen(_ t: WeinPreisTreffer) {
        besterPreis = zahl(t.preis)
        besterHaendler = t.haendler
        besterURL = t.url ?? ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func istUebernommen(_ t: WeinPreisTreffer) -> Bool {
        Coerce.double(besterPreis).map { abs($0 - t.preis) < 0.005 } == true && besterHaendler == t.haendler
    }

    private func person(_ owner: String) -> String {
        switch owner {
        case "lars": return "Lars"
        case "elita": return "Elita"
        default: return owner.capitalized
        }
    }

    private func zahl(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.2f", d)
    }

    private func euro(_ d: Double) -> String { String(format: "%.2f", d) + " €" }

    private func kurz(_ url: String) -> String {
        guard let host = URL(string: url)?.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func jsonText(_ werte: [String]) -> String {
        (try? JSONSerialization.data(withJSONObject: werte))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}

// MARK: - Bausteine (dateiprivat, damit sie nicht mit den Atomen der übrigen Wein-Dateien kollidieren)

/// Eine Option des Geschmacksrichtung-Pickers. Eigener Typ statt Tupel, weil `ForEach(_:id:)`
/// einen KeyPath braucht und Tupel keine KeyPaths haben.
private struct WeinGeschmacksrichtung: Identifiable {
    let id: String      // exakt der CHECK-Wert der Spalte
    let label: String
}

/// Regler für ein Geschmacksmerkmal (1 bis 5). Ganz links = keine Angabe (NULL in der DB).
private struct WeinProfilRegler: View {
    let titel: String
    let links: String
    let rechts: String
    @Binding var wert: Int?
    let kennung: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(titel).font(.subheadline)
                Spacer(minLength: 8)
                Text(wert.map { String($0) + " von 5" } ?? "keine Angabe")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(wert ?? 0) },
                                  set: { neu in
                                      let i = Int(neu.rounded())
                                      wert = i == 0 ? nil : i
                                  }),
                   in: 0...5, step: 1)
                .accessibilityIdentifier(kennung)
                .accessibilityLabel(titel)
            HStack {
                Text(links)
                Spacer(minLength: 8)
                Text(rechts)
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Editierbare Tag-Chips (Rebsorten, Aromen, Auszeichnungen): antippen entfernt, Feld + Plus fügt hinzu.
private struct WeinTagFeld: View {
    let platzhalter: String
    @Binding var tags: [String]
    let kennung: String
    var farbe: Color = Theme.accent
    @State private var neu = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { i, t in
                        Button { tags.remove(at: i) } label: {
                            HStack(spacing: 4) {
                                Text(t)
                                Image(systemName: "xmark.circle.fill").font(.caption2)
                            }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(farbe.opacity(0.15), in: Capsule())
                            .foregroundStyle(farbe)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(kennung + "-chip-" + String(i))
                    }
                }
            }
            HStack(spacing: 8) {
                TextField(platzhalter, text: $neu)
                    .autocorrectionDisabled()
                    .onSubmit(hinzufuegen)
                    .accessibilityIdentifier(kennung + "-feld")
                Button(action: hinzufuegen) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(farbe)
                }
                .buttonStyle(.borderless)
                .disabled(neu.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier(kennung + "-add")
            }
            .font(.subheadline)
        }
    }

    private func hinzufuegen() {
        let t = neu.trimmingCharacters(in: .whitespacesAndNewlines)
        neu = ""
        guard !t.isEmpty, !tags.contains(t) else { return }
        tags.append(t)
    }
}

/// Sterne nur zur Anzeige (Bewertungen des vorhandenen Weins in der Dubletten-Karte).
private struct WeinSterneAnzeige: View {
    let sterne: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= sterne ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(i <= sterne ? Color.yellow : Color.secondary.opacity(0.4))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Bewertung " + String(sterne) + " von 5")
    }
}
