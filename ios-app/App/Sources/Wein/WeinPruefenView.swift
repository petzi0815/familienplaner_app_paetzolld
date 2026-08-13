import SwiftUI
import UIKit

/// Wofür die Maske gerade offen ist. Steuert nur, was WEGFÄLLT bzw. hinzukommt — die Feldgruppen
/// selbst sind in beiden Modi dieselben, sonst driftet das Bearbeiten vom Anlegen weg.
enum WeinMaskeModus {
    /// Schritt 2 der Erfassung: Dubletten-Karte, KI-Analyse-Kopf, Anlegen und danach bewerten.
    case anlegen
    /// Vorhandener Eintrag: PATCH auf die ID, Etikett ersetzen, neu erkennen lassen.
    case bearbeiten
}

/// Schritt 2 der Erfassung: alles, was die KI ermittelt hat, wird sichtbar und ist editierbar —
/// gegliedert in Getränkeart / Wein bzw. Spirituose / Herkunft / Geschmack / Hintergrund / Preis /
/// Keller. Vertrauensgrad, Hinweise und die Quellen-Links stehen oben. Erst der Speichern-Knopf legt
/// den Datensatz an (Etikettenfoto zuerst hochladen, damit die Flasche gleich mit `foto_key`
/// entsteht), danach kann direkt die eigene Sterne-Bewertung gesetzt werden.
///
/// ART-ABHÄNGIG: der Umschalter ganz oben entscheidet, welche Feldgruppe erscheint — Wein
/// (Jahrgang, Weinart, Rebsorten, Lage, Geschmacksrichtung, Profil, Trinkfenster) oder Spirituose
/// (Kategorie, Stil, Alter, Fass, Abfülljahr, Trinkempfehlung, Cocktails). Umschalten LÖSCHT nichts:
/// die Eingaben der Gegenart bleiben im Formular stehen, gehen aber nicht mit — `patchFelder()`
/// schickt nur die Spalten der gewählten Art (dieselbe Trennung nimmt das Backend beim Erfassen
/// vor). Wer eine falsch erkannte Art korrigiert, verliert dadurch nichts.
///
/// Meldet das Backend eine Dublette, steht ganz oben eine Karte mit den vorhandenen Bewertungen und
/// zwei Wegen: vorhandene Flasche öffnen oder trotzdem als eigenen Eintrag anlegen (anderer
/// Jahrgang bzw. andere Abfüllung).
///
/// ZWEI MODI, EINE MASKE (`WeinMaskeModus`): dieselbe Maske legt an (Schritt 2 der Erfassung) und
/// bearbeitet einen vorhandenen Eintrag (`init(bearbeiten:)`, Einstieg über den Toolbar-Knopf der
/// Detailseite bzw. „Von Hand ausfüllen" in der Warteschlange). Bewusst KEINE zweite Maske: alle
/// art-abhängigen Feldgruppen, die Vorbelegung aus DB-Spaltennamen und die Trennung der Spalten
/// beider Getränkearten stehen hier bereits — eine Kopie liefe binnen einer Änderung auseinander.
/// Im Bearbeiten-Modus entfallen Dubletten-Karte, KI-Analyse-Kopf und Bewertungsblock (bewertet
/// wird auf der Detailseite), dafür gibt es Etikett ersetzen und „Erneut erkennen lassen".
/// Gespeichert wird dort per PATCH auf die vorhandene ID.
///
/// Wird von `WeinErfassenView` gepusht und lebt in dessen NavigationStack — hier KEIN eigener Stack.
/// Im Bearbeiten-Modus liegt sie in einem Sheet, dessen NavigationStack der Aufrufer stellt.
struct WeinPruefenView: View {
    let vorschlag: WeinVorschlag
    /// Etikettenfoto aus Schritt 1 (wird beim Speichern hochgeladen).
    var foto: UIImage? = nil
    /// Nach dem Anlegen mit der neuen Wein-ID gerufen.
    var onGespeichert: (Int) -> Void = { _ in }
    /// Vorhandenen Wein aus der Dubletten-Karte öffnen.
    var onDubletteOeffnen: (Int) -> Void = { _ in }
    /// Schließt den gesamten Erfassungs-Flow (nicht nur diesen Bildschirm).
    /// Im Bearbeiten-Modus schließt es das Sheet.
    var schliessen: () -> Void = {}
    /// Anlegen oder Bearbeiten. Wird nicht direkt gesetzt, sondern über `init(bearbeiten:)`.
    var modus: WeinMaskeModus = .anlegen
    /// Zeile, auf die im Bearbeiten-Modus gespeichert wird. Im Anlege-Modus nil — dort entsteht die
    /// ID erst beim ersten Speichern.
    var bearbeiteId: Int?

    @EnvironmentObject private var store: WeinStore

    // ── Getränkeart ──
    @State private var art: GetraenkeArt = .wein
    // ── Wein bzw. Spirituose ──
    @State private var name = ""
    @State private var weingut = ""          // bei Spirituosen die Destillerie bzw. Marke
    @State private var jahrgang = ""
    @State private var typ: WeinTyp = .rot
    @State private var rebsorten: [String] = []
    @State private var flaschengroesse = "750"
    @State private var ean = ""
    // Nur Spirituosen — bleiben beim Umschalten stehen, gehen aber nur bei art == .spirituose mit.
    @State private var kategorie: SpirituosenKategorie?
    @State private var stil = ""
    @State private var alterJahre = ""
    @State private var fass = ""
    @State private var abgefuelltJahr = ""
    @State private var trinkempfehlung = ""
    @State private var cocktails: [String] = []
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
    /// Gebäude, in dem die Flasche steht — für beide Getränkearten bedienbar (siehe `kellerSection`
    /// und `patchFelder()`). Fehlender Wert = zu Hause, der Default der Spalte (sie ist NOT NULL).
    @State private var standort: WeinStandort = .zuhause

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

    // ── Nur Bearbeiten-Modus ──
    /// Neu aufgenommenes bzw. gewähltes Etikett. Hochgeladen wird es erst beim Speichern (wie im
    /// Anlege-Fluss) — wer abbricht, hat nichts verändert.
    @State private var neuesFoto: UIImage?
    @State private var fotoQuelle: ImageSource?
    /// Wartet das neue Etikett noch auf den Upload? Ein Bild ändert `patchFelder()` NICHT — ohne
    /// diese Merkung bliebe der Speichern-Knopf gesperrt und das Foto unspeicherbar.
    @State private var fotoOffen = false
    @State private var erkennungLaeuft = false

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
        // Der Abbrechen-Knopf haengt am ganzen Formular und nicht als leerer ToolbarItem-Platzhalter
        // in beiden Modi: er sitzt vorne in der Navigationsleiste, wo im Anlege-Fluss der
        // Zurueck-Pfeil steht — dort gar keinen Platz zu belegen ist der einzige Weg, den
        // bestehenden Weg sicher unveraendert zu lassen. Ein eigener Ausstieg ist ohnehin nur im
        // Bearbeiten-Modus noetig (Sheet); die Erfassung bringt ihr „Abbrechen" schon mit.
        Group {
            if istBearbeiten {
                formular.toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { schliessen() }
                            .accessibilityIdentifier("wein-bearbeiten-abbrechen")
                    }
                }
            } else {
                formular
            }
        }
        .navigationTitle(maskenTitel)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: vorbefuellen)
    }

    private var formular: some View {
        Form {
            artSection
            kopf
            weinSection
            herkunftSection
            geschmackSection
            hintergrundSection
            preisSection
            kellerSection
            abschluss
        }
    }

    /// Ein einziger Ort für die Modus-Frage. Über Mustervergleich statt `==`, damit `WeinMaskeModus`
    /// keine Protokolle braucht.
    private var istBearbeiten: Bool {
        if case .bearbeiten = modus { return true }
        return false
    }

    /// Titel der Maske. Im Bearbeiten-Modus mit der Getränkeart, damit auf einen Blick klar ist,
    /// welche Feldgruppen unten stehen.
    private var maskenTitel: String {
        istBearbeiten ? art.einzahl + " bearbeiten" : "Prüfen und speichern"
    }

    // MARK: - Getränkeart

    /// Steht ganz oben, weil sie über die gesamte Maske entscheidet. Vorbelegt aus dem Vorschlag
    /// (das Backend erkennt die Art und schlägt sie mit) — hat die Erkennung danebengelegen, wird
    /// hier korrigiert, ohne dass etwas verloren geht.
    private var artSection: some View {
        Section {
            Picker("Getränkeart", selection: $art) {
                ForEach(GetraenkeArt.allCases) { a in
                    Text(a.emoji + " " + a.label).tag(a)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("wein-pruefen-art")
        } footer: {
            Text("Umschalten löscht nichts: Angaben der anderen Art bleiben stehen, gespeichert wird nur, was zur gewählten Art gehört.")
        }
    }

    // MARK: - Kopf: Dublette + Vertrauensgrad

    /// Beides gehört zum frischen KI-Lauf und entfällt deshalb im Bearbeiten-Modus: eine Dublette
    /// meldet nur der Scan, und „Vertrauen unbekannt" über einem längst gepflegten Eintrag wäre eine
    /// Aussage über eine Analyse, die gar nicht stattgefunden hat.
    @ViewBuilder private var kopf: some View {
        if !istBearbeiten {
            if let d = vorschlag.dublette, !dubletteWeggeklickt, gespeicherteId == nil {
                dubletteSection(d)
            }
            vertrauenSection
        }
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
                        // Die Dublettensuche laeuft art-getrennt — die vorhandene Flasche ist
                        // also immer von derselben Art wie die gerade erfasste.
                        Label(art.einzahl + " öffnen", systemImage: "arrow.up.forward.app")
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
            // Spirituosen haben keinen Jahrgang — dort unterscheidet die Abfüllung (Alter, Fass,
            // Batch) die zweite Flasche von der ersten.
            Text(art == .wein
                 ? "Anderer Jahrgang oder eine zweite Flasche? Dann trotzdem als eigenen Eintrag anlegen."
                 : "Andere Abfüllung oder eine zweite Flasche? Dann trotzdem als eigenen Eintrag anlegen.")
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

    // MARK: - Wein bzw. Spirituose

    /// Gemeinsamer Rahmen (Hersteller, Name, Flaschengröße, EAN, Foto) mit der art-spezifischen
    /// Feldgruppe in der Mitte. Bewusst in kleine Bausteine zerlegt: ein einziger großer
    /// ViewBuilder mit `if`-Zweigen treibt die Übersetzungszeit des Typecheckers hoch.
    private var weinSection: some View {
        Section {
            TextField(herstellerLabel, text: $weingut)
                .accessibilityIdentifier("wein-pruefen-weingut")
            TextField(nameLabel, text: $name)
                .accessibilityIdentifier("wein-pruefen-name")
            if art == .wein { weinFelder } else { spirituosenFelder }
            TextField("Flaschengröße in ml", text: $flaschengroesse)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("wein-pruefen-flaschengroesse")
            TextField("EAN", text: $ean)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("wein-pruefen-ean")
            fotoBereich
        } header: {
            Text(art.einzahl)
        }
    }

    /// Anlegen: das Etikett aus Schritt 1 wird nur angezeigt (aufgenommen wurde es dort).
    /// Bearbeiten: es lässt sich ersetzen oder erstmals hinzufügen.
    @ViewBuilder private var fotoBereich: some View {
        if istBearbeiten {
            fotoBearbeiten
        } else if let img = foto {
            fotoZeile(img)
        }
    }

    /// Nur Wein: Jahrgang, Weinart und Rebsorten.
    /// Der Picker heißt „Weinart" und nicht mehr „Art" — „Art" ist jetzt der Getränkeart-Umschalter
    /// ganz oben, zwei gleich benannte Auswahlfelder auf einem Bildschirm wären eine Falle.
    @ViewBuilder private var weinFelder: some View {
        TextField("Jahrgang (leer = jahrgangslos)", text: $jahrgang)
            .keyboardType(.numberPad)
            .accessibilityIdentifier("wein-pruefen-jahrgang")
        Picker("Weinart", selection: $typ) {
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
    }

    /// Nur Spirituosen: Kategorie, Stil, Alter, Fass und Abfülljahr.
    /// „Keine Angabe" ist ein eigener, gültiger Zustand — `kategorie` bleibt dann NULL, statt
    /// „sonstiges" zu behaupten, was der Datensatz nicht hergibt.
    @ViewBuilder private var spirituosenFelder: some View {
        Picker("Kategorie", selection: $kategorie) {
            Text("Keine Angabe").tag(SpirituosenKategorie?.none)
            ForEach(SpirituosenKategorie.allCases) { k in
                Text(k.emoji + " " + k.label).tag(SpirituosenKategorie?.some(k))
            }
        }
        .accessibilityIdentifier("wein-pruefen-kategorie")
        TextField("Stil (z. B. Single Malt Islay)", text: $stil)
            .accessibilityIdentifier("wein-pruefen-stil")
        TextField("Alter in Jahren (leer = ohne Altersangabe)", text: $alterJahre)
            .keyboardType(.numberPad)
            .accessibilityIdentifier("wein-pruefen-alter")
        TextField("Fass / Reifung (z. B. Ex-Bourbon, Oloroso-Finish)", text: $fass)
            .accessibilityIdentifier("wein-pruefen-fass")
        TextField("Abfülljahr (Single Cask / Batch)", text: $abgefuelltJahr)
            .keyboardType(.numberPad)
            .accessibilityIdentifier("wein-pruefen-abgefuellt-jahr")
    }

    private func fotoZeile(_ img: UIImage) -> some View {
        HStack(spacing: 12) {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("Etikettenfoto wird mitgespeichert.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    /// Etikett im Bearbeiten-Modus: Zustand zeigen, neu aufnehmen oder aus der Mediathek wählen.
    /// Aufbau wie `WeinFotoFeld` in Schritt 1, nur mit eigenen Identifiern (jenes ist dateiprivat).
    private var fotoBearbeiten: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                fotoVorschau
                Text(fotoHinweis).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            HStack(spacing: 16) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { fotoQuelle = ImageSource(.camera) } label: {
                        Label(fotoVorhanden ? "Neu aufnehmen" : "Fotografieren", systemImage: "camera.fill")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("wein-bearbeiten-foto")
                }
                Button { fotoQuelle = ImageSource(.photoLibrary) } label: {
                    Label(fotoVorhanden ? "Anderes Bild" : "Mediathek", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("wein-bearbeiten-mediathek")
                Spacer(minLength: 0)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 2)
        .sheet(item: $fotoQuelle) { q in
            ImagePicker(sourceType: q.type) { bild in
                neuesFoto = bild
                fotoOffen = true
            }
        }
    }

    /// Vorschau des NEUEN Bildes. Das bereits gespeicherte Etikett wird bewusst NICHT über
    /// `AuthImage` gezeigt: das braucht `AppState` aus der Umgebung, und ein Sheet erbt die
    /// EnvironmentObjects seines Aufrufers nicht verlässlich — die Maske würde je nach Einstieg
    /// abstürzen. Dass ein Etikett hinterlegt ist, sagt stattdessen `fotoHinweis`.
    @ViewBuilder private var fotoVorschau: some View {
        if let img = neuesFoto {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(akzent.opacity(0.15))
                .frame(width: 56, height: 56)
                .overlay(Image(systemName: fotoVorhanden ? "photo" : "camera")
                    .foregroundStyle(akzent))
        }
    }

    /// Liegt schon ein Etikett vor — neu aufgenommen oder beim Datensatz gespeichert?
    private var fotoVorhanden: Bool {
        neuesFoto != nil || Coerce.str(vorschlag.felder["foto_key"]) != nil
    }

    private var fotoHinweis: String {
        if neuesFoto != nil { return "Neues Etikett wird beim Speichern hochgeladen." }
        return fotoVorhanden ? "Etikettenfoto ist gespeichert." : "Noch kein Etikettenfoto."
    }

    // MARK: - Herkunft

    private var herkunftSection: some View {
        Section {
            TextField("Land", text: $land)
                .accessibilityIdentifier("wein-pruefen-land")
            TextField("Region", text: $region)
                .accessibilityIdentifier("wein-pruefen-region")
            // Die Einzellage gibt es nur beim Wein; bei Spirituosen steht die Herkunft in Land
            // und Region (die Destillerie selbst im Hersteller-Feld).
            if art == .wein {
                TextField("Lage / Weinberg", text: $lage)
                    .accessibilityIdentifier("wein-pruefen-lage")
            }
        } header: {
            Text("Herkunft")
        }
    }

    // MARK: - Geschmack

    /// Bio/Vegan gelten für beide Arten (Bio-Gin gibt es reichlich) und stehen deshalb außerhalb
    /// der art-spezifischen Blöcke — die Reihenfolge der Weinfelder bleibt dadurch unverändert.
    private var geschmackSection: some View {
        Section {
            if art == .wein { geschmackWeinFelder } else { geschmackSpirituosenFelder }
            Toggle("Bio", isOn: $bio)
                .accessibilityIdentifier("wein-pruefen-bio")
            Toggle("Vegan", isOn: $vegan)
                .accessibilityIdentifier("wein-pruefen-vegan")
        } header: {
            Text("Geschmack")
        } footer: {
            Text(art == .wein
                 ? "Die Regler sind 1 bis 5. Ganz links heißt: keine Angabe."
                 : "Süße, Säure, Tannin und Körper beschreiben Wein — bei Spirituosen zählen Aromen, Fass und die Trinkempfehlung.")
        }
    }

    @ViewBuilder private var geschmackWeinFelder: some View {
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

        aromenFeld

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
    }

    /// Nur Spirituosen: kein Geschmacksprofil und kein Trinkfenster (eine geschlossene Flasche
    /// reift nicht weiter) — dafür Trinkempfehlung und passende Cocktails.
    @ViewBuilder private var geschmackSpirituosenFelder: some View {
        TextField("Alkohol in Volumenprozent", text: $alkohol)
            .keyboardType(.decimalPad)
            .accessibilityIdentifier("wein-pruefen-alkohol")

        aromenFeld

        TextField("Trinkempfehlung (z. B. pur, on the rocks)", text: $trinkempfehlung, axis: .vertical)
            .lineLimit(1...3)
            .accessibilityIdentifier("wein-pruefen-trinkempfehlung")

        VStack(alignment: .leading, spacing: 6) {
            Text("Cocktails").font(.caption).foregroundStyle(.secondary)
            WeinTagFeld(platzhalter: "Cocktail hinzufügen", tags: $cocktails,
                        kennung: "wein-pruefen-cocktails", farbe: akzent)
        }

        TextField("Serviertemperatur (z. B. 18-20 °C)", text: $serviertemperatur)
            .accessibilityIdentifier("wein-pruefen-serviertemperatur")
    }

    /// Aromen — für beide Arten gleich, deshalb an einer Stelle.
    private var aromenFeld: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Aromen").font(.caption).foregroundStyle(.secondary)
            WeinTagFeld(platzhalter: "Aroma hinzufügen", tags: $aromen,
                        kennung: "wein-pruefen-aromen", farbe: akzent)
        }
    }

    // MARK: - Hintergrund

    private var hintergrundSection: some View {
        Section {
            TextField(beschreibungLabel, text: $beschreibung, axis: .vertical)
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
            // Für BEIDE Getränkearten: geparkt wird, wo zu Hause der Platz fehlt — das trifft die
            // Weinkiste genauso wie die Ginflasche. Steht direkt unter dem Lagerort, weil beides
            // zusammen die Antwort ergibt: welches Gebäude, und darin welches Regal („im Büro, dort
            // im Schrank links").
            Picker("Standort", selection: $standort) {
                ForEach(WeinStandort.allCases) { s in
                    Text(s.emoji + " " + s.label).tag(s)
                }
            }
            .accessibilityIdentifier("wein-pruefen-standort")
        } header: {
            Text("Keller")
        } footer: {
            Text("Im Büro geparkte Flaschen bleiben vollständig im Bestand — sie werden nur zusätzlich gekennzeichnet.")
        }
    }

    // MARK: - Speichern + eigene Bewertung

    @ViewBuilder private var abschluss: some View {
        if !fehler.isEmpty {
            Section { Text(fehler).font(.footnote).foregroundStyle(.red) }
        }
        Section {
            Button {
                Task {
                    let angekommen = await speichern()
                    // Bearbeiten ist mit dem Speichern erledigt — die Detailseite dahinter zeigt
                    // den frischen Stand aus dem Store. Beim Anlegen bleibt die Maske stehen, weil
                    // danach noch die eigene Bewertung folgt.
                    if angekommen, istBearbeiten { schliessen() }
                }
            } label: {
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
                      || (gespeicherteId != nil && !offeneAenderung))
            .accessibilityIdentifier("wein-pruefen-speichern")
        } footer: {
            if gespeicherteId == nil {
                Text("Ein Name genügt zum Speichern. Alles andere lässt sich später ergänzen.")
            } else if offeneAenderung {
                Text("Es gibt noch nicht gespeicherte Änderungen.")
            }
        }
        // Bewertet wird beim Anlegen (frisch angelegte Flasche) — beim Bearbeiten steht der
        // Bewertungsblock schon auf der Detailseite, von der die Maske aufgerufen wurde.
        if istBearbeiten { erkennungSection }
        else if gespeicherteId != nil { bewertungSection }
    }

    // MARK: - Erneut erkennen lassen (nur Bearbeiten)

    /// Der Weg, einen falsch erkannten Eintrag komplett neu bewerten zu lassen. Die Kette liest
    /// Etikett und Barcode noch einmal und überschreibt AUSSCHLIESSLICH ihre eigenen Felder — was
    /// von Hand gepflegt wurde (Bestand, Standort, Lagerort, Notizen, gekaufter Preis), bleibt
    /// stehen; das entscheidet die Weißliste im Backend.
    private var erkennungSection: some View {
        Section {
            if let grund = kiFehlerText {
                Text("Fehler: " + grund).font(.footnote).foregroundStyle(.red)
            }
            Button { Task { await erneutErkennen() } } label: {
                HStack(spacing: 8) {
                    if erkennungLaeuft { ProgressView() }
                    Text(erkennungLaeuft ? "Erkennung läuft …" : "Erneut erkennen lassen")
                }
            }
            .disabled(speichert || erkennungLaeuft || gespeicherteId == nil)
            .accessibilityIdentifier("wein-bearbeiten-erneut")
        } header: {
            Text("Erkennung")
        } footer: {
            Text("Das dauert einen Moment. Eigene Angaben — Bestand, Lagerort, Standort, Notizen und der bezahlte Preis — bleiben unangetastet.")
        }
    }

    /// Klartext des letzten Fehlschlags, wenn die Hintergrund-Erkennung an dieser Flasche
    /// gescheitert ist. Steht nur bei `fehler` da: bei einem laufenden Versuch ist der alte Grund
    /// überholt und würde wie ein aktuelles Problem aussehen.
    private var kiFehlerText: String? {
        guard Coerce.str(vorschlag.felder["ki_status"]) == WeinKiStatus.fehler.rawValue else { return nil }
        return Coerce.str(vorschlag.felder["ki_fehler"])
    }

    private func erneutErkennen() async {
        guard let id = gespeicherteId else { return }
        erkennungLaeuft = true
        // Offene Korrektur ZUERST abschicken — die Erkennung liest die Zeile vom Server; ein hier
        // korrigierter Barcode oder eine korrigierte Getränkeart käme sonst gar nicht bei ihr an.
        // Kam der Stand nicht durch, bleibt die Maske mit der Fehlermeldung stehen.
        if offeneAenderung {
            let angekommen = await speichern()
            if !angekommen {
                erkennungLaeuft = false
                return
            }
        }
        await store.anreicherungStarten(id: id)
        erkennungLaeuft = false
        // Danach schliessen: die Maske hält jetzt einen veralteten Stand. Wer sie offen liesse und
        // später speicherte, schriebe die frisch erkannten Werte mit den alten wieder zu.
        schliessen()
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
            Text("Optional. Du kannst " + artAkkusativ + " auch später bewerten.")
        }
    }

    // MARK: - Vorbefüllen

    private func vorbefuellen() {
        guard !vorbefuellt else { return }
        vorbefuellt = true
        let f = vorschlag.felder

        // Zuerst die Art — an ihr haengen Maske, Vorgabewerte und was gespeichert wird. Fehlt sie
        // (manueller Weg, aelteres Backend), gilt die im Bereich zuletzt gewaehlte.
        art = GetraenkeArt(rawValue: Coerce.str(f["art"]) ?? "") ?? store.art

        name = Coerce.str(f["name"]) ?? ""
        weingut = Coerce.str(f["weingut"]) ?? ""
        if let j = Coerce.int(f["jahrgang"]) { jahrgang = String(j) }
        // Spirituosen haben keine Weinfarbe: ohne Angabe „sonstiges" statt „rot" — die Spalte ist
        // NOT NULL, ein stiller Default 'rot' an einem Whisky waere schlicht falsch.
        typ = WeinTyp(rawValue: Coerce.str(f["typ"]) ?? "") ?? (art == .wein ? .rot : .sonstiges)
        rebsorten = Coerce.stringArray(f["rebsorten"])
        kategorie = SpirituosenKategorie(rawValue: Coerce.str(f["kategorie"]) ?? "")
        stil = Coerce.str(f["stil"]) ?? ""
        if let a = Coerce.int(f["alter_jahre"]), a > 0 { alterJahre = String(a) }
        fass = Coerce.str(f["fass"]) ?? ""
        if let j = Coerce.int(f["abgefuellt_jahr"]), j > 0 { abgefuelltJahr = String(j) }
        trinkempfehlung = Coerce.str(f["trinkempfehlung"]) ?? ""
        cocktails = Coerce.stringArray(f["cocktails"])
        if let g = Coerce.int(f["flaschengroesse_ml"]), g > 0 { flaschengroesse = String(g) }
        else { flaschengroesse = String(standardFlaschengroesse) }
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
        // Fehlender/unbekannter Wert = zu Hause (Default der Migration). Die KI liefert den
        // Standort nie — über den Einkaufs-Scan kann aber ein vorhandener Datensatz hier landen,
        // und dessen Parkplatz darf beim Speichern nicht still auf „zu Hause" zurückfallen.
        standort = WeinStandort(rawValue: Coerce.str(f["standort"]) ?? "") ?? .zuhause
        quelle = Coerce.str(f["quelle"]) ?? "ki"

        // Bearbeiten: die Zeile gibt es schon, ab jetzt geht jedes Speichern als PATCH auf ihre ID.
        // Der gerade eingelesene Stand IST der gespeicherte — dadurch steht der Knopf auf
        // „Gespeichert", bis wirklich etwas geändert wurde, statt eine unveränderte Zeile noch
        // einmal zurückzuschreiben.
        if istBearbeiten, let id = bearbeiteId {
            gespeicherteId = id
            gespeicherterStand = patchFelder() as NSDictionary
        }
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
        if let img = hochzuladendesFoto, let jpeg = img.jpegForUpload() {
            if let key = try? await store.api.uploadFoto(jpeg: jpeg) {
                felder["foto_key"] = key
            }
        }
        let id = await store.save(felder, id: gespeicherteId)
        if let id {
            gespeicherteId = id
            gespeicherterStand = stand as NSDictionary
            // Das Etikett liegt jetzt beim Server — ein zweites Speichern soll es nicht noch einmal
            // hochladen (jeder Upload legt eine neue Datei an).
            fotoOffen = false
            // Nur das Anlegen ist fuer den Aufrufer neu; der PATCH hat den Store bereits aktualisiert.
            if neu { onGespeichert(id) }
        } else {
            fehler = neu
                ? artArtikel + " konnte nicht gespeichert werden. Bitte noch einmal versuchen."
                : "Die Änderungen konnten nicht gespeichert werden. Bitte noch einmal versuchen."
        }
        speichert = false
        return id != nil
    }

    /// Bild, das dieser Speicherlauf hochladen muss — sonst nil.
    /// Anlegen: das Etikett aus Schritt 1, aber NUR beim ersten Mal (ein Korrektur-PATCH würde
    /// dasselbe Bild sonst erneut ablegen). Bearbeiten: das neu gewählte, solange es noch nicht
    /// oben ist.
    private var hochzuladendesFoto: UIImage? {
        if gespeicherteId == nil { return foto }
        return fotoOffen ? neuesFoto : nil
    }

    /// Beschriftung des Speichern-Knopfs: anlegen → gespeichert → offene Korrektur.
    private var speichernTitel: String {
        if gespeicherteId == nil { return "Speichern" }
        return offeneAenderung ? "Änderungen speichern" : "Gespeichert"
    }

    /// Gibt es überhaupt etwas abzuschicken? Neben den Feldern zählt das noch nicht hochgeladene
    /// Etikett mit — es steht in keinem Feld und bliebe sonst für immer im Formular hängen.
    private var offeneAenderung: Bool { geaendert || fotoOffen }

    /// Weicht das Formular vom zuletzt gespeicherten Stand ab? Vor dem ersten Speichern immer true.
    private var geaendert: Bool {
        guard let stand = gespeicherterStand else { return true }
        return !stand.isEqual(patchFelder() as NSDictionary)
    }

    /// Felder in DB-Schreibweise. Listen gehen als JSON-Text raus.
    /// LEERE EINGABEN: beim Anlegen bleiben sie weg (die Spalte bekommt ihren DB-Default), beim
    /// Bearbeiten gehen sie als JSON-`null` mit — siehe `setzeOderLeere`.
    /// ART-ABHAENGIG: die Spalten der jeweils ANDEREN Getraenkeart bleiben komplett draussen. Sie
    /// stehen zwar noch im Formular (Umschalten wirft nichts weg), gehoeren aber nicht in die Zeile —
    /// sonst traegt ein korrigierter Whisky weiter Rebsorten und Trinkfenster mit sich herum.
    private func patchFelder() -> [String: Any] {
        // `typ` ist NOT NULL und kennt nur Weinfarben — fuer Spirituosen der neutrale Auffangwert
        // statt des DB-Defaults 'rot'. Vorab berechnet (und nicht als Ternaeroperator im
        // Dictionary-Literal), damit der Typechecker nicht ueber `Any` raten muss.
        let typWert: WeinTyp = art == .wein ? typ : .sonstiges
        let ml = Int(flaschengroesse.trimmingCharacters(in: .whitespaces)) ?? standardFlaschengroesse
        var f: [String: Any] = [
            "art": art.rawValue,
            "name": name.trimmingCharacters(in: .whitespaces),
            "weingut": weingut.trimmingCharacters(in: .whitespaces),
            "typ": typWert.rawValue,
            "aromen": jsonText(aromen),
            "auszeichnungen": jsonText(auszeichnungen),
            "bio": bio ? 1 : 0,
            "vegan": vegan ? 1 : 0,
            "flaschengroesse_ml": ml,
            "preis_beobachten": beobachten ? 1 : 0,
            "bestand": bestand,
            "quelle": quelleSicher,
        ]
        // Der Standort geht für BEIDE Getränkearten mit — anders als `typ` oben, obwohl er lange
        // an der Art hing: solange es den Umschalter nur bei Spirituosen gab, hätte „im Büro parken
        // → Art auf Wein korrigieren" einen Wein mit `standort='buero'` hinterlassen, der überall
        // das Büro-Abzeichen trug, während das Bedienelement dafür bei Weinen fehlte — ein Zustand
        // ohne Bedienelement. Genau das ist weg: Knopf, Abzeichen und Filter gibt es jetzt bei
        // beiden Arten, also darf der Wert die Korrektur der Art überleben. Ihn weiterhin
        // zurückzusetzen würde die Angabe beim Umschalten still wegwerfen.
        f["standort"] = standort.rawValue
        // Gemeinsame Textspalten; die art-eigenen kommen unten dazu.
        var texte: [(String, String)] = [
            ("land", land), ("region", region),
            ("serviertemperatur", serviertemperatur), ("ean", ean),
            ("beschreibung", beschreibung), ("speiseempfehlung", speiseempfehlung),
            ("bester_preis_haendler", besterHaendler), ("bester_preis_url", besterURL),
            ("gekauft_bei", gekauftBei), ("lagerort", lagerort), ("notizen", notizen),
        ]
        switch art {
        case .wein:
            f["rebsorten"] = jsonText(rebsorten)
            f["geschmacksrichtung"] = geschmacksrichtung
            texte.append(("lage", lage))
            setzeOderLeere(&f, "jahrgang", Int(jahrgang.trimmingCharacters(in: .whitespaces)))
            setzeOderLeere(&f, "suesse", suesse)
            setzeOderLeere(&f, "saeure", saeure)
            setzeOderLeere(&f, "tannin", tannin)
            setzeOderLeere(&f, "koerper", koerper)
            setzeOderLeere(&f, "trinkfenster_von", Int(trinkfensterVon.trimmingCharacters(in: .whitespaces)))
            setzeOderLeere(&f, "trinkfenster_bis", Int(trinkfensterBis.trimmingCharacters(in: .whitespaces)))
        case .spirituose:
            f["cocktails"] = jsonText(cocktails)
            texte.append(contentsOf: [("stil", stil), ("fass", fass),
                                      ("trinkempfehlung", trinkempfehlung)])
            setzeOderLeere(&f, "kategorie", kategorie?.rawValue)
            setzeOderLeere(&f, "alter_jahre", positiveZahl(alterJahre))
            setzeOderLeere(&f, "abgefuellt_jahr", positiveZahl(abgefuelltJahr))
        }
        setzeOderLeere(&f, "alkohol", Coerce.double(alkohol))
        setzeOderLeere(&f, "referenzpreis", Coerce.double(referenzpreis))
        setzeOderLeere(&f, "bester_preis", Coerce.double(besterPreis))
        setzeOderLeere(&f, "gekauft_preis", Coerce.double(gekauftPreis))
        for (spalte, wert) in texte {
            let t = wert.trimmingCharacters(in: .whitespacesAndNewlines)
            // Explizit typisiert statt als Ternaeroperator im Aufruf: der Helfer ist generisch,
            // und ein blankes `nil` im Argument gaebe ihm nichts, woraus er T ableiten kann.
            let text: String? = t.isEmpty ? nil : t
            setzeOderLeere(&f, spalte, text)
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

    /// Setzt eine NULL-bare Spalte — oder leert sie im Bearbeiten-Modus ausdruecklich.
    ///
    /// WARUM: ein PATCH aendert nur, was im Body steht. Wer eine falsche Region, einen falschen
    /// Jahrgang oder eine falsche Kategorie herausloescht, schickt ohne dieses `null` gar nichts —
    /// der alte Wert bliebe stehen, und genau das Korrigieren ist der Zweck des Modus. Beim
    /// ANLEGEN gibt es dagegen nichts zu loeschen: dort bleibt die Spalte weg und behaelt ihren
    /// DB-Default (`quelle`, Listen, `standort` …), was fuer NOT-NULL-Spalten der einzige gangbare
    /// Weg ist.
    ///
    /// Die Unterscheidung haengt bewusst am MODUS und nicht an „schon gespeichert": `istBearbeiten`
    /// steht fuer die Lebensdauer der Maske fest, also hat das Dictionary immer dieselbe Gestalt.
    /// Wuerde die Gestalt nach dem ersten Speichern umspringen, meldete `geaendert` sofort eine
    /// offene Aenderung, ohne dass jemand etwas angefasst hat.
    ///
    /// NUR fuer NULL-bare Spalten aufrufen — bei NOT-NULL-Spalten (name, weingut, typ, art,
    /// bestand, flaschengroesse_ml, die JSON-Listen, quelle, standort, geschmacksrichtung) waere
    /// `null` ein Constraint-Fehler; die stehen deshalb weiterhin fest im Dictionary.
    /// Generisch statt `Any?`, damit aus einem `Int?` kein verschachteltes Optional wird, das als
    /// „gesetzt" durchginge.
    private func setzeOderLeere<T>(_ f: inout [String: Any], _ spalte: String, _ wert: T?) {
        if let wert {
            f[spalte] = wert
        } else if istBearbeiten {
            // NSNull ist der Weg zu JSON-`null`: JSONSerialization schreibt dafuer `null`, und das
            // generische CRUD setzt die Spalte damit wirklich auf NULL.
            f[spalte] = NSNull()
        }
    }

    /// Jahresangabe aus einem Eingabefeld. 0 und Unfug gelten als „nicht angegeben" — eine
    /// Altersangabe von 0 Jahren oder ein Abfuelljahr 0 gibt es nicht.
    private func positiveZahl(_ eingabe: String) -> Int? {
        guard let i = Int(eingabe.trimmingCharacters(in: .whitespaces)), i > 0 else { return nil }
        return i
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

    /// Beschriftung des Hersteller-Feldes. Bei Spirituosen steht in derselben Spalte `weingut` die
    /// Destillerie bzw. die Marke (Gin und Likör tragen oft gar keine Destillerie im Namen).
    private var herstellerLabel: String { art == .wein ? "Weingut" : "Destillerie / Marke" }
    private var nameLabel: String { art == .wein ? "Name des Weins" : "Name der Spirituose" }
    private var beschreibungLabel: String {
        art == .wein
            ? "Beschreibung (Weingut, Lage, Ausbau)"
            : "Beschreibung (Destillerie, Herstellung, Reifung)"
    }
    /// Mit Artikel, damit die Fehlermeldung grammatisch stimmt („Der Wein" / „Die Spirituose").
    private var artArtikel: String { art == .wein ? "Der Wein" : "Die Spirituose" }
    /// Dasselbe im Akkusativ („… den Wein bewerten" / „… die Spirituose bewerten").
    private var artAkkusativ: String { art == .wein ? "den Wein" : "die Spirituose" }
    /// Uebliche Flaschengroesse der Art — Wein 0,75 l, Spirituosen 0,7 l.
    private var standardFlaschengroesse: Int { art == .wein ? 750 : 700 }

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

// MARK: - Einstieg „Bearbeiten"

/// Der Einstieg steht BEWUSST in einer Extension und nicht im Rumpf der View: ein Initialisierer
/// im Rumpf würde den vom Compiler erzeugten memberwise-Initialisierer verdrängen — und genau den
/// ruft `WeinErfassenView` für den Anlege-Fluss auf.
extension WeinPruefenView {
    /// Vorhandenen Eintrag in derselben Maske bearbeiten.
    /// Die Werte kommen als `WeinVorschlag` herein, weil die Maske ihre Vorbelegung ohnehin aus
    /// DB-Spaltennamen liest (`vorbefuellen()`): so gibt es genau EINEN Vorbelegungsweg statt
    /// zweier, die auseinanderlaufen können.
    init(bearbeiten wein: Wein, schliessen: @escaping () -> Void = {}) {
        let vorschlag = WeinVorschlag(felder: WeinPruefenView.bearbeitungsFelder(wein),
                                      preise: [], quellen: [], confidence: "unbekannt",
                                      hinweise: [], dublette: nil)
        self.init(vorschlag: vorschlag,
                  schliessen: schliessen,
                  modus: .bearbeiten,
                  bearbeiteId: wein.id)
    }

    /// Feldwerte eines vorhandenen Eintrags in DB-Schreibweise.
    /// `patchFields` liefert fast alles, lässt aber bewusst weg, was allein der Server setzt. Drei
    /// davon stehen in dieser Maske trotzdem als Eingabefelder und müssen deshalb vorbelegt werden:
    /// bester Preis, Händler und Link — sonst gingen sie beim ersten Speichern verloren, weil
    /// `patchFelder()` sie aus leeren Feldern gar nicht erst mitschickt.
    /// `ki_status`/`ki_fehler` kommen nur zur ANZEIGE mit (Fehlergrund im Erkennungs-Abschnitt);
    /// zurückgeschrieben werden sie nie — `patchFelder()` baut sein Dictionary von Grund auf neu.
    static func bearbeitungsFelder(_ w: Wein) -> [String: Any] {
        var f = w.patchFields
        if let p = w.besterPreis { f["bester_preis"] = p }
        if let h = w.besterPreisHaendler, !h.isEmpty { f["bester_preis_haendler"] = h }
        if let u = w.besterPreisURL, !u.isEmpty { f["bester_preis_url"] = u }
        f["ki_status"] = w.kiStatus.rawValue
        if let e = w.kiFehler, !e.isEmpty { f["ki_fehler"] = e }
        return f
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
