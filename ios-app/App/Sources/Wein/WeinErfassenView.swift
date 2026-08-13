import SwiftUI
import UIKit

/// Einzelerfassung (Wein ODER Spirituose). Drei Einstiege — Etikett fotografieren, EAN scannen
/// oder von Hand tippen —, die aber NICHT dasselbe tun:
///
///   * **Foto und EAN reihen ein** (`store.erfassen` → POST /api/v1/wein-erfassen). Der Server legt
///     die Zeile sofort an und erkennt sie im Hintergrund; das Blatt schließt sich unmittelbar.
///     Vorher lief hier die volle Kette live (`/wein-scan`, OpenAI + Perplexity + OpenAI) und der
///     Nutzer sah zwanzig Sekunden und länger eine Fortschrittsanzeige — genau das, was die
///     Reihenerfassung längst besser macht. Wer eine Flasche in der Hand hält, will sie loswerden
///     und nicht bei ihr stehen bleiben.
///   * **Von Hand geht weiter über die Prüfmaske** (`WeinPruefenView`, Schritt 2). Dort gibt es
///     nichts zu erkennen — wer tippt, hat die Angaben ja schon —, und die Maske IST das
///     Eingabeformular. Sie einzureihen hieße, dieselben Felder gleich noch einmal zu erfragen.
///
/// Ganz oben steht der Getränkeart-Umschalter. Er geht als `art` mit und ist nur ein HINWEIS:
/// erkennt die Kette am Etikett bzw. am Barcode etwas anderes, gewinnt die Erkennung (im Laden
/// schaltet niemand erst um, bevor er scannt).
///
/// Wird als Sheet präsentiert (eigener NavigationStack). Schritt 2 wird gepusht — closure-basiert
/// über `navigationDestination(isPresented:)`, nicht wertbasiert (siehe Lernpunkt Geschenkplaner).
struct WeinErfassenView: View {
    /// Vorbelegter Barcode — kommt aus dem Einkaufs-Scan im Laden. Ohne ihn müsste der Nutzer
    /// dieselbe Flasche ein zweites Mal scannen, und der Wein entstünde ohne EAN.
    var startEan: String = ""
    /// Im Einkaufs-Scan bereits recherchierter Vorschlag. Liegt er vor, springt die Erfassung
    /// direkt in Schritt 2 — die (kostenpflichtige) KI-Kette läuft dann kein zweites Mal.
    var startVorschlag: WeinVorschlag? = nil
    /// Vorbelegtes Regal/Fach. Wird beim Einreihen mitgeschickt, damit die Flasche im Keller nicht
    /// unter „Ohne Lagerort" landet und hinterher einzeln nachgetragen werden muss.
    var startLagerort: String = ""
    /// Vorbelegtes Gebäude (zuhause | Büro). Beantwortet eine andere Frage als `startLagerort` und
    /// gilt neben ihm — wer im Büro einräumt, meint jede Flasche dieses Durchgangs.
    var startStandort: WeinStandort? = nil
    /// Nach dem Anlegen mit der neuen Wein-ID gerufen (z. B. um die Liste zu aktualisieren).
    var onGespeichert: (Int) -> Void = { _ in }
    /// Vorhandenen Wein öffnen — kommt aus der Dubletten-Karte in Schritt 2.
    var onDubletteOeffnen: (Int) -> Void = { _ in }

    @EnvironmentObject private var store: WeinStore
    @Environment(\.dismiss) private var dismiss

    // Eingaben
    @State private var foto: UIImage?
    @State private var ean = ""
    @State private var weingut = ""
    @State private var name = ""
    /// Rohtext des dritten Feldes: bei Wein der Jahrgang, bei Spirituosen die Altersangabe.
    /// EIN Feld für beide, damit der Identifier `wein-erfassen-jahrgang` (XCUITest) bleibt und
    /// ein Umschalten die Eingabe nicht wegwirft.
    @State private var jahrgang = ""
    @State private var hinweis = ""
    /// Vom Nutzer gewählte Getränkeart. nil = Umschalter noch nicht angefasst → es gilt `startArt`.
    /// Der Umweg über Optional erspart eine Zuweisung in `vorbelegen()`: `store` steht beim
    /// Initialisieren der States noch nicht bereit, und ein Nachsetzen im `.task` ließe den
    /// Umschalter beim ersten Bild sichtbar umspringen.
    @State private var artWahl: GetraenkeArt?

    // Ablauf
    @State private var zeigeScanner = false
    /// Der Upload läuft (Sekunden, nicht Minuten — erkannt wird erst danach im Hintergrund).
    @State private var laeuft = false
    @State private var fehler = ""
    @State private var vorschlag: WeinVorschlag?
    @State private var zeigePruefen = false
    /// Übernahme aus dem Einkaufs-Scan darf nur EINMAL laufen (siehe `vorbelegen()`).
    @State private var vorbelegt = false

    var body: some View {
        NavigationStack {
            Form {
                artSection
                fotoSection
                barcodeSection
                manuellSection
                hinweisSection
                aktionSection
            }
            .navigationTitle(art.einzahl + " erfassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .accessibilityIdentifier("wein-erfassen-abbrechen")
                }
            }
            .sheet(isPresented: $zeigeScanner) { scannerSheet }
            .navigationDestination(isPresented: $zeigePruefen) {
                if let v = vorschlag {
                    WeinPruefenView(vorschlag: v,
                                    foto: foto,
                                    onGespeichert: { id in onGespeichert(id) },
                                    onDubletteOeffnen: { id in dismiss(); onDubletteOeffnen(id) },
                                    schliessen: { dismiss() })
                        // Schritt 2 braucht den Store; navigationDestination-Ziele erben
                        // EnvironmentObjects nicht zuverlaessig → explizit durchreichen.
                        .environmentObject(store)
                }
            }
            .task { await vorbelegen() }
        }
    }

    // MARK: - Übernahme aus dem Einkaufs-Scan

    /// Barcode und fertigen Vorschlag aus dem Laden übernehmen. Ist der Vorschlag da, geht es
    /// ohne Umweg in Schritt 2 — die KI hat den Wein bereits recherchiert, ein zweiter Lauf
    /// kostet nur Geld und Wartezeit (kein Etikettenfoto: im Laden wurde keins gemacht).
    ///
    /// Läuft bewusst nur EINMAL: sonst würde die Rückkehr aus Schritt 2 sofort wieder dorthin
    /// pushen und der Nutzer käme nicht mehr an das Formular.
    @MainActor
    private func vorbelegen() async {
        guard !vorbelegt else { return }
        vorbelegt = true
        let start = startEan.trimmingCharacters(in: .whitespaces)
        if ean.isEmpty { ean = start }
        guard var v = startVorschlag else { return }
        // Der gescannte Barcode gehört in den Datensatz — sonst meldet der nächste Regal-Scan
        // dieselbe Flasche wieder als unbekannt.
        if Coerce.str(v.felder["ean"]) == nil, !start.isEmpty { v.felder["ean"] = start }
        // Ohne erkannte Art (älteres Backend) gilt die hier vorbelegte — sonst zeigte Schritt 2
        // eine andere Maske, als der Umschalter oben behauptet.
        if GetraenkeArt(rawValue: Coerce.str(v.felder["art"]) ?? "") == nil {
            v.felder["art"] = art.rawValue
        }
        vorschlag = v
        // Ein Moment Vorlauf: `navigationDestination` greift nicht zuverlässig, wenn das Ziel
        // schon während des ersten Layouts gesetzt wird.
        try? await Task.sleep(nanoseconds: 50_000_000)
        zeigePruefen = true
    }

    // MARK: - Abschnitte

    /// Getränkeart. Steht ganz oben, weil sie bestimmt, wonach recherchiert wird und welche Felder
    /// Schritt 2 zeigt. Vorbelegt mit dem, was der Bereich gerade zeigt (`store.art`) — wer im
    /// Spirituosen-Tab auf „erfassen" tippt, meint fast immer eine Spirituose.
    private var artSection: some View {
        Section {
            Picker("Getränkeart", selection: artBindung) {
                ForEach(GetraenkeArt.allCases) { a in
                    Text(a.emoji + " " + a.label).tag(a)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("wein-erfassen-art")
        } footer: {
            // „Im nächsten Schritt" gibt es für Foto und EAN nicht mehr — die Maske ist nach dem
            // Einreihen zu. Korrigiert wird eine falsch geratene Art danach am Eintrag selbst.
            Text("Erkennt die KI am Etikett eine andere Art, gewinnt die Erkennung. Ändern geht später jederzeit am Eintrag.")
        }
    }

    private var fotoSection: some View {
        Section {
            WeinFotoFeld(bild: $foto)
        } header: {
            Text("Etikett fotografieren")
        } footer: {
            Text("Das Etikett wird im Hintergrund ausgelesen. Das Bild bleibt als Etikettenfoto am Eintrag.")
        }
    }

    private var barcodeSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("EAN / Barcode", text: $ean)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("wein-erfassen-ean")
                if !ean.isEmpty {
                    Button { ean = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wein-erfassen-ean-loeschen")
                }
            }
            if BarcodeScannerView.isSupported {
                Button { zeigeScanner = true } label: {
                    Label("Barcode scannen", systemImage: "barcode.viewfinder")
                }
                .accessibilityIdentifier("wein-erfassen-scan")
            }
        } header: {
            Text("Barcode")
        } footer: {
            Text(art == .wein
                 ? "Viele Weine haben eine EAN auf der Rückseite. Damit findet die Recherche im Hintergrund oft direkt den passenden Jahrgang."
                 : "Fast jede Flasche hat eine EAN auf der Rückseite. Damit findet die Recherche im Hintergrund oft direkt die richtige Abfüllung.")
        }
    }

    private var manuellSection: some View {
        Section {
            TextField(herstellerLabel, text: $weingut)
                .accessibilityIdentifier("wein-erfassen-weingut")
            TextField(nameLabel, text: $name)
                .accessibilityIdentifier("wein-erfassen-name")
            TextField(jahrLabel, text: $jahrgang)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("wein-erfassen-jahrgang")
        } header: {
            Text("Von Hand")
        } footer: {
            // Getippte Angaben gehen NICHT mit ans Einreihen — die Route dort kennt nur Bild und
            // Barcode. Das muss hier stehen, sonst tippt jemand drei Felder voll und wundert sich,
            // warum davon nichts ankommt.
            Text(art == .wein
                 ? "Weingut, Name und Jahrgang gehören zum Weg von Hand — dafür der Knopf unten. Beim Einreihen zählen Foto und EAN."
                 : "Destillerie, Name und Altersangabe gehören zum Weg von Hand — dafür der Knopf unten. Beim Einreihen zählen Foto und EAN.")
        }
    }

    private var hinweisSection: some View {
        Section {
            TextField("Zusatzangaben (optional)", text: $hinweis, axis: .vertical)
                .lineLimit(1...3)
                .accessibilityIdentifier("wein-erfassen-hinweis")
        } header: {
            Text("Hinweis")
        } footer: {
            Text(art == .wein
                 ? "Alles, was hilft: Rebsorte, Region, Händler. Wird beim Weg von Hand als Notiz übernommen."
                 : "Alles, was hilft: Stil, Fassreifung, Region, Händler. Wird beim Weg von Hand als Notiz übernommen.")
        }
    }

    private var aktionSection: some View {
        Section {
            // Beschriftung = Wirkung: der Knopf reiht ein, er erkennt nicht. Ein Knopf, der etwas
            // anderes tut als er verspricht, ist schlimmer als der alte, langsame Ablauf.
            Button { Task { await einreihen() } } label: {
                HStack(spacing: 8) {
                    if laeuft { ProgressView() }
                    Text(laeuft ? "Wird eingereiht ..." : "Einreihen")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(laeuft || !einreihbar)
            .accessibilityIdentifier("wein-erfassen-start")

            Button("Von Hand ausfüllen") { manuellWeiter() }
                .font(.subheadline)
                .disabled(laeuft)
                .accessibilityIdentifier("wein-erfassen-manuell")

            if !fehler.isEmpty {
                Text(fehler).font(.footnote).foregroundStyle(.red)
            }
        } footer: {
            Text(einreihbar
                 ? "Die Flasche wird sofort angelegt; Etikett lesen, Hintergrund und Preise suchen laufen danach im Hintergrund. Dieses Blatt schließt sich dabei."
                 : "Zum Einreihen genügt ein Etikettenfoto oder eine EAN. Wer nur tippt, nimmt den Weg von Hand.")
        }
    }

    private var scannerSheet: some View {
        NavigationStack {
            BarcodeScannerView { code in
                ean = code
                zeigeScanner = false
            }
            .ignoresSafeArea()
            .navigationTitle("Barcode scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { zeigeScanner = false }
                        .accessibilityIdentifier("wein-erfassen-scanner-abbrechen")
                }
            }
        }
    }

    // MARK: - Ableitungen

    /// Gültige Vorbelegung des Umschalters, solange der Nutzer ihn nicht angefasst hat: hat der
    /// Einkaufs-Scan schon eine Art erkannt, gilt sie — sonst die im Bereich zuletzt gewählte.
    private var startArt: GetraenkeArt {
        if let v = startVorschlag,
           let erkannt = GetraenkeArt(rawValue: Coerce.str(v.felder["art"]) ?? "") { return erkannt }
        return store.art
    }

    /// Die aktuell gültige Getränkeart (Nutzerwahl schlägt Vorbelegung).
    private var art: GetraenkeArt { artWahl ?? startArt }

    private var artBindung: Binding<GetraenkeArt> {
        Binding(get: { art }, set: { artWahl = $0 })
    }

    /// Beschriftung des Hersteller-Feldes. Bei Spirituosen steht in derselben Spalte `weingut` die
    /// Destillerie bzw. die Marke (Gin und Likör haben oft keine Destillerie im Namen).
    private var herstellerLabel: String { art == .wein ? "Weingut" : "Destillerie / Marke" }
    private var nameLabel: String { art == .wein ? "Name des Weins" : "Name der Spirituose" }
    private var jahrLabel: String { art == .wein ? "Jahrgang" : "Alter in Jahren" }

    private var eanSauber: String { ean.trimmingCharacters(in: .whitespaces) }
    private var weingutSauber: String { weingut.trimmingCharacters(in: .whitespaces) }
    private var nameSauber: String { name.trimmingCharacters(in: .whitespaces) }

    /// Einreihen geht NUR mit Etikettenfoto oder Barcode: die Warteschlange erkennt genau daraus.
    /// Eine Zeile ohne beides wäre eine leere Flasche im Inventar, die niemand mehr zuordnen kann —
    /// getippte Angaben nehmen deshalb den Weg von Hand.
    private var einreihbar: Bool { foto != nil || !eanSauber.isEmpty }

    // MARK: - Einreihen (Foto- und EAN-Weg)

    /// Flasche einreihen und das Blatt schließen. Hier wird bewusst NICHT auf die Erkennung
    /// gewartet: der Server legt die Zeile sofort an, die Kette (Etikett lesen, Recherche, Preise)
    /// läuft danach im Hintergrund, und die Liste zeigt den Eintrag derweil in der Warteschlange.
    /// Das ist derselbe Weg wie in der Reihenerfassung — nur für eine einzelne Flasche.
    @MainActor
    private func einreihen() async {
        guard !laeuft, einreihbar else { return }
        laeuft = true
        fehler = ""
        // Der Umschalter dieser Maske ist die Ansage des Nutzers, welche Getränkeart er gerade
        // pflegt. `store.erfassen` schickt `store.art` mit, und der Bereich filtert danach: ohne
        // diese Übernahme ginge die Flasche als Wein weg UND die frisch eingereihte Zeile wäre
        // hinter dem Umschalter versteckt — der Toast meldete etwas, das man nirgends sieht.
        if store.art != art { store.art = art }
        // 1600 px reichen für ein Etikett und halten den Upload auch im Laden klein (gleiche
        // Kantenlänge wie in der Reihenerfassung — dieselbe Erkennungskette dahinter).
        let jpeg = foto?.jpegForUpload(maxEdge: 1600)
        if foto != nil, jpeg == nil {
            // Lieber hier stehen bleiben als eine Zeile ohne Bild einreihen, die nie erkannt wird.
            laeuft = false
            fehler = "Das Foto ließ sich nicht aufbereiten. Bitte noch einmal aufnehmen."
            return
        }
        let ok = await store.erfassen(image: jpeg,
                                      ean: eanSauber.isEmpty ? nil : eanSauber,
                                      standort: startStandort,
                                      lagerort: startLagerort.isEmpty ? nil : startLagerort)
        laeuft = false
        guard ok else {
            // Den Klartext des Fehlers hat der Store schon als Meldung gesetzt — die liegt aber
            // hinter diesem Blatt. Deshalb hier eine eigene Zeile, damit der Nutzer überhaupt
            // merkt, dass nichts eingereiht wurde, und es erneut versuchen kann.
            fehler = "Das Einreihen hat nicht geklappt. Bitte noch einmal versuchen."
            return
        }
        // Die Rückmeldung im Klartext („… eingereiht — wird jetzt erkannt") kommt vom Store und
        // erscheint als Toast im Bereich; die Liste hat er ebenfalls schon nachgezogen.
        dismiss()
    }

    /// Die eine Zahl aus dem dritten Eingabefeld in die richtige Spalte legen: Wein → `jahrgang`,
    /// Spirituose → `alter_jahre`. Bei umgeschalteter Art ist ein „2019" dort KEINE Altersangabe —
    /// lieber nichts eintragen als 2019 Jahre Fassreifung zu behaupten.
    private func uebernehmeJahreszahl(_ zahl: Int, zielArt: GetraenkeArt, in f: inout [String: Any]) {
        if zielArt == .wein {
            if Coerce.int(f["jahrgang"]) == nil { f["jahrgang"] = zahl }
        } else if (1...100).contains(zahl), Coerce.int(f["alter_jahre"]) == nil {
            f["alter_jahre"] = zahl
        }
    }

    /// Der Weg von Hand: die getippten Angaben in die Prüfmaske übernehmen (Schritt 2). Hier gibt
    /// es nichts zu erkennen — wer Weingut, Name und Jahrgang selbst eintippt, braucht weder
    /// Etikett-Vision noch Recherche —, und die Prüfmaske ist ohnehin das Eingabeformular.
    /// Deshalb bleibt genau dieser Weg unverändert, während Foto und EAN einreihen.
    private func manuellWeiter() {
        var f: [String: Any] = ["quelle": "manuell", "art": art.rawValue]
        if !nameSauber.isEmpty { f["name"] = nameSauber }
        if !weingutSauber.isEmpty { f["weingut"] = weingutSauber }
        if let zahl = Int(jahrgang.trimmingCharacters(in: .whitespaces)) {
            uebernehmeJahreszahl(zahl, zielArt: art, in: &f)
        }
        if !eanSauber.isEmpty { f["ean"] = eanSauber }
        // Eine Vorbelegung gilt für beide Wege: sonst müsste der Nutzer das Regal, das er gerade
        // einräumt, in der Prüfmaske noch einmal eintippen.
        if !startLagerort.isEmpty { f["lagerort"] = startLagerort }
        if let s = startStandort { f["standort"] = s.rawValue }
        let h = hinweis.trimmingCharacters(in: .whitespacesAndNewlines)
        if !h.isEmpty { f["notizen"] = h }
        vorschlag = WeinVorschlag(felder: f, preise: [], quellen: [], confidence: "niedrig",
                                  hinweise: ["Ohne KI-Recherche erfasst. Bitte alle Angaben selbst ergänzen."],
                                  dublette: nil)
        fehler = ""
        zeigePruefen = true
    }
}

// MARK: - Etikettenfoto

/// Kamera oder Mediathek mit Vorschau und Entfernen. Bindet ein `UIImage?`; hochgeladen wird es
/// erst beim Speichern in Schritt 2 (Muster: `Vorrat/VorratPhotoField.swift`).
private struct WeinFotoFeld: View {
    @Binding var bild: UIImage?
    @State private var quelle: ImageSource?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let img = bild {
                HStack(spacing: 12) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Button { bild = nil } label: {
                        Label("Entfernen", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("wein-erfassen-foto-entfernen")
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 16) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { quelle = ImageSource(.camera) } label: {
                        Label(bild == nil ? "Fotografieren" : "Neu aufnehmen", systemImage: "camera.fill")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("wein-erfassen-foto")
                }
                Button { quelle = ImageSource(.photoLibrary) } label: {
                    Label(bild == nil ? "Mediathek" : "Anderes Bild", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("wein-erfassen-mediathek")
                Spacer(minLength: 0)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 2)
        .sheet(item: $quelle) { s in
            ImagePicker(sourceType: s.type) { bild = $0 }
        }
    }
}
