import SwiftUI
import UIKit

/// Schritt 1 der Wein-Erfassung. Drei gleichwertige Einstiege — Etikett fotografieren, EAN scannen
/// oder von Hand tippen — und EIN Knopf, der die Erkennung samt Recherche im Backend anstößt
/// (POST /api/v1/wein-scan). Hier wird NICHTS gespeichert: die Antwort landet als `WeinVorschlag`
/// in Schritt 2 (`WeinPruefenView`), wo jedes Feld geprüft und erst dann angelegt wird.
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
    @State private var jahrgang = ""
    @State private var hinweis = ""

    // Ablauf
    @State private var zeigeScanner = false
    @State private var laeuft = false
    @State private var schritt = ""
    @State private var fehler = ""
    @State private var vorschlag: WeinVorschlag?
    @State private var zeigePruefen = false
    /// Übernahme aus dem Einkaufs-Scan darf nur EINMAL laufen (siehe `vorbelegen()`).
    @State private var vorbelegt = false

    var body: some View {
        NavigationStack {
            Form {
                fotoSection
                barcodeSection
                manuellSection
                hinweisSection
                aktionSection
            }
            .navigationTitle("Wein erfassen")
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
        vorschlag = v
        // Ein Moment Vorlauf: `navigationDestination` greift nicht zuverlässig, wenn das Ziel
        // schon während des ersten Layouts gesetzt wird.
        try? await Task.sleep(nanoseconds: 50_000_000)
        zeigePruefen = true
    }

    // MARK: - Abschnitte

    private var fotoSection: some View {
        Section {
            WeinFotoFeld(bild: $foto)
        } header: {
            Text("Etikett fotografieren")
        } footer: {
            Text("Die KI liest das Etikett aus. Das Bild wird danach als Etikettenfoto gespeichert.")
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
            Text("Viele Weine haben eine EAN auf der Rückseite. Damit findet die Recherche oft direkt den passenden Jahrgang.")
        }
    }

    private var manuellSection: some View {
        Section {
            TextField("Weingut", text: $weingut)
                .accessibilityIdentifier("wein-erfassen-weingut")
            TextField("Name des Weins", text: $name)
                .accessibilityIdentifier("wein-erfassen-name")
            TextField("Jahrgang", text: $jahrgang)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("wein-erfassen-jahrgang")
        } header: {
            Text("Von Hand")
        } footer: {
            Text("Weingut, Name und Jahrgang genügen. Den Rest recherchiert die KI.")
        }
    }

    private var hinweisSection: some View {
        Section {
            TextField("Zusatzangaben (optional)", text: $hinweis, axis: .vertical)
                .lineLimit(1...3)
                .accessibilityIdentifier("wein-erfassen-hinweis")
        } header: {
            Text("Hinweis für die KI")
        } footer: {
            Text("Alles, was hilft: Rebsorte, Region, Händler oder was sonst auf dem Etikett steht.")
        }
    }

    private var aktionSection: some View {
        Section {
            Button { Task { await analysieren() } } label: {
                HStack(spacing: 8) {
                    if laeuft { ProgressView() }
                    Text(laeuft ? schritt : "Erkennen und recherchieren")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(laeuft || !bereit)
            .accessibilityIdentifier("wein-erfassen-start")

            Button("Ohne Recherche weiter") { manuellWeiter() }
                .font(.subheadline)
                .disabled(laeuft)
                .accessibilityIdentifier("wein-erfassen-manuell")

            if !fehler.isEmpty {
                Text(fehler).font(.footnote).foregroundStyle(.red)
            }
        } footer: {
            Text(laeuft
                 ? "Das dauert ein paar Sekunden."
                 : "Etikett bzw. Barcode lesen, Hintergrund und aktuelle Preise suchen. Gespeichert wird noch nichts.")
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

    private var eanSauber: String { ean.trimmingCharacters(in: .whitespaces) }
    private var weingutSauber: String { weingut.trimmingCharacters(in: .whitespaces) }
    private var nameSauber: String { name.trimmingCharacters(in: .whitespaces) }

    /// Mindestens ein Einstieg muss belegt sein, sonst hat die KI nichts zu tun.
    private var bereit: Bool {
        foto != nil || !eanSauber.isEmpty || !nameSauber.isEmpty || !weingutSauber.isEmpty
    }

    /// Woher die Angaben stammen (CHECK-Werte der Spalte `quelle`).
    private var quelleWert: String {
        if foto != nil { return "foto" }
        if !eanSauber.isEmpty { return "ean" }
        return "ki"
    }

    /// Freitext für die Analyse: die manuellen Felder plus der Zusatzhinweis.
    private var freitext: String? {
        var teile: [String] = []
        if !weingutSauber.isEmpty { teile.append("Weingut: " + weingutSauber) }
        if !nameSauber.isEmpty { teile.append("Name: " + nameSauber) }
        let j = jahrgang.trimmingCharacters(in: .whitespaces)
        if !j.isEmpty { teile.append("Jahrgang: " + j) }
        let h = hinweis.trimmingCharacters(in: .whitespacesAndNewlines)
        if !h.isEmpty { teile.append(h) }
        return teile.isEmpty ? nil : teile.joined(separator: ", ")
    }

    // MARK: - Analyse

    private func analysieren() async {
        laeuft = true
        fehler = ""
        schritt = foto != nil ? "Etikett lesen ..." : "Wein nachschlagen ..."
        // Zweiter Fortschrittstext, damit die mehrsekündige Kette nicht wie ein Hänger wirkt.
        let ticker = Task { await fortschrittTicken() }
        do {
            let ergebnis = try await store.api.scan(image: foto?.jpegForUpload(),
                                                    ean: eanSauber.isEmpty ? nil : eanSauber,
                                                    text: freitext)
            ticker.cancel()
            vorschlag = angereichert(ergebnis)
            laeuft = false
            schritt = ""
            zeigePruefen = true
        } catch {
            ticker.cancel()
            laeuft = false
            schritt = ""
            fehler = (error as? APIError)?.errorDescription ?? "Die Analyse hat nicht geklappt."
        }
    }

    private func fortschrittTicken() async {
        try? await Task.sleep(nanoseconds: 3_500_000_000)
        guard !Task.isCancelled else { return }
        schritt = "Preise und Hintergrund recherchieren ..."
    }

    /// Eigene Eingaben gewinnen dort, wo die KI nichts geliefert hat (sie kennt EAN/Notizen nicht).
    private func angereichert(_ v: WeinVorschlag) -> WeinVorschlag {
        var f = v.felder
        if Coerce.str(f["ean"]) == nil, !eanSauber.isEmpty { f["ean"] = eanSauber }
        if Coerce.str(f["weingut"]) == nil, !weingutSauber.isEmpty { f["weingut"] = weingutSauber }
        if Coerce.str(f["name"]) == nil, !nameSauber.isEmpty { f["name"] = nameSauber }
        if Coerce.int(f["jahrgang"]) == nil, let j = Int(jahrgang.trimmingCharacters(in: .whitespaces)) {
            f["jahrgang"] = j
        }
        if Coerce.str(f["quelle"]) == nil { f["quelle"] = quelleWert }
        return WeinVorschlag(felder: f, preise: v.preise, quellen: v.quellen,
                             confidence: v.confidence, hinweise: v.hinweise, dublette: v.dublette)
    }

    /// Ohne KI weiter (kein OpenAI-Key, kein Netz oder schlicht schneller von Hand).
    private func manuellWeiter() {
        var f: [String: Any] = ["quelle": "manuell"]
        if !nameSauber.isEmpty { f["name"] = nameSauber }
        if !weingutSauber.isEmpty { f["weingut"] = weingutSauber }
        if let j = Int(jahrgang.trimmingCharacters(in: .whitespaces)) { f["jahrgang"] = j }
        if !eanSauber.isEmpty { f["ean"] = eanSauber }
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
