import AVFoundation
import SwiftUI
import UIKit

// Reihenerfassung — der schnelle Weg, ein ganzes Regal ins Inventar zu bekommen.
//
// Der Unterschied zur Erfassung ueber `WeinErfassenView` ist die Zusage an den Nutzer: hier wird
// NICHT gewartet und NICHT geprueft. Jede Ausloesung geht sofort als eigene Zeile an den Server
// (`/wein-erfassen`), der sie anlegt und im Hintergrund erkennt; die Kamera bleibt derweil offen.
// Deshalb laufen die Uploads nebenlaeufig und die Zaehlung liegt HIER und nicht in der Ansicht:
//
//   * Der `WeinSerienLauf` gehoert dem Bereich (`WeinRootView`), nicht der Kamera. Er ueberlebt
//     dadurch das Schliessen — sonst ginge die Bilanz der letzten Flasche verloren, deren Upload
//     beim Zuklappen noch lief, und der Abschluss-Toast waere zu niedrig.
//   * Fehlgeschlagene Uploads (Flugmodus, Server weg) werden gezaehlt und am Ende genannt. Sie
//     duerfen NIE still verschwinden — das ist der Kern der Zusage "nichts geht verloren".
//   * Waehrend der Serie gibt es KEINE Einzel-Toasts und KEIN Nachladen (`store.erfassen(serie:)`
//     unterdrueckt beides): ein Toast je Foto wuerde den naechsten ueberschreiben, und eine volle
//     Liste je Foto waere reine Verschwendung. Nachgeladen wird einmal am Ende.

/// Bilanz einer laufenden Serie: was ausgeloest wurde, was ankam, was fehlschlug.
/// Bewusst eine Klasse und kein `@State`-Wert: die Zaehler werden aus nebenlaeufigen Aufgaben
/// hochgezaehlt, die das Schliessen der Kamera ueberleben.
@MainActor
final class WeinSerienLauf: ObservableObject {
    /// Vom Server bestaetigt eingereiht.
    @Published private(set) var eingereiht = 0
    /// Upload fehlgeschlagen (kein Netz, Server-Fehler, unbrauchbares Bild).
    @Published private(set) var fehlgeschlagen = 0
    /// Noch unterwegs — steht in der Fahne als "wird gesendet".
    @Published private(set) var offen = 0

    /// Laufende Uploads. Der Abschluss wartet sie ab, bevor er die Bilanz meldet.
    private var aufgaben: [Task<Void, Never>] = []

    /// Ausgeloest insgesamt (auch das, was noch unterwegs ist) — die Zahl auf der Fahne.
    var ausgeloest: Int { eingereiht + fehlgeschlagen + offen }

    /// Text der Zaehler-Fahne. Jede Form muss auch bei 0 und bei 1 stimmen, deshalb die Faelle
    /// einzeln; Zahlen immer ueber `String(...)` (sonst wuerde aus 1024 ein "1.024").
    var stand: String {
        if ausgeloest == 0 { return "Noch keine Flasche" }
        var text = ausgeloest == 1 ? "1 Flasche" : String(ausgeloest) + " Flaschen"
        if offen > 0 { text += " · " + String(offen) + " wird gesendet" }
        if fehlgeschlagen > 0 { text += " · " + String(fehlgeschlagen) + " Fehler" }
        return text
    }

    /// Vor jeder neuen Serie: bei null anfangen.
    func neu() {
        aufgaben = []
        eingereiht = 0
        fehlgeschlagen = 0
        offen = 0
    }

    /// Eine Flasche einreihen (Foto ODER Barcode). Kehrt SOFORT zurueck — die Kamera darf auf
    /// nichts warten; der Upload laeuft in einer eigenen Aufgabe weiter.
    func einreihen(store: WeinStore, image: UIImage? = nil, ean: String? = nil) {
        offen += 1
        // Haptik statt Toast: waehrend die Kamera offen ist, ist ein Impuls die einzige
        // Rueckmeldung, die den Sucher nicht verdeckt.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let aufgabe = Task { [self] in
            var jpeg: Data?
            if let image {
                // Verkleinern kostet spuerbar Rechenzeit. Abseits des Hauptlaufs, damit die Kamera
                // zwischen zwei Ausloesungen nicht stockt (`UIGraphicsImageRenderer` darf das).
                // 1600 px reichen fuer ein Etikett und halten den Upload im Laden klein.
                jpeg = await Task.detached(priority: .userInitiated) {
                    image.jpegForUpload(maxEdge: 1600)
                }.value
            }
            let ok: Bool
            if image != nil && jpeg == nil {
                // Bild liess sich nicht kodieren — zaehlt als Fehler statt lautlos zu verschwinden.
                ok = false
            } else {
                ok = await store.erfassen(image: jpeg, ean: ean, serie: true)
            }
            offen = max(0, offen - 1)
            if ok { eingereiht += 1 } else { fehlgeschlagen += 1 }
        }
        aufgaben.append(aufgabe)
    }

    /// Serie beenden: auf die noch laufenden Uploads warten, die Liste einmal nachziehen und die
    /// Bilanz in EINEM Satz melden. Wird vom Bereich beim Schliessen der Kamera aufgerufen.
    func abschluss(store: WeinStore) async {
        for a in aufgaben { await a.value }
        aufgaben = []
        // Kamera geoeffnet und gleich wieder zu: keine Meldung ueber nichts.
        guard eingereiht + fehlgeschlagen > 0 else {
            neu()
            return
        }
        // Erst nachladen, dann melden — sonst steht der Toast ueber einer Liste, in der die frisch
        // eingereihten Flaschen noch fehlen.
        await store.reload()
        store.notify(meldung(), error: fehlgeschlagen > 0)
        neu()
    }

    /// Abschlussmeldung. Der Nutzer soll ohne Nachdenken sehen, was angekommen ist — und was nicht.
    private func meldung() -> String {
        if eingereiht == 0 {
            return fehlgeschlagen == 1
                ? "1 Flasche konnte nicht gesendet werden"
                : String(fehlgeschlagen) + " Flaschen konnten nicht gesendet werden"
        }
        let kern = eingereiht == 1
            ? "1 Flasche eingereiht — wird erkannt"
            : String(eingereiht) + " Flaschen eingereiht — werden erkannt"
        if fehlgeschlagen == 0 { return kern }
        return kern + " · " + String(fehlgeschlagen) + " nicht gesendet"
    }
}

// MARK: - Serie 1: fotografieren

/// Kamera im Dauerbetrieb: Flasche anvisieren, ausloesen, naechste Flasche. Kein
/// Bestaetigungsschirm, kein Schliessen zwischendurch — beendet wird ueber „Fertig".
///
/// Der Sucher kommt aus `WeinKamera.swift` (AVFoundation). Warum NICHT
/// `UIImagePickerController` mit eigener `cameraOverlayView`, steht dort ausfuehrlich: dessen
/// Vorschau ist fest 4:3 (schwarzes unteres Drittel), seine Ebene haengt ausserhalb der
/// SwiftUI-Hierarchie (Knoepfe reagieren nicht) und kennt die sicheren Bereiche nicht (Text unter
/// der Dynamic Island).
///
/// Der Aufbau hier ist genau die Antwort darauf: EIN ZStack, unten der Sucher mit
/// `.ignoresSafeArea()`, darueber die Bedienelemente OHNE — dadurch weichen Zaehler und Knoepfe
/// automatisch der Dynamic Island und dem Home-Indikator aus.
struct WeinSerienFotoView: View {
    @ObservedObject var lauf: WeinSerienLauf
    /// Store bewusst durchgereicht statt `@EnvironmentObject`: eine vollflaechig praesentierte
    /// Ansicht erbt die Umgebungsobjekte des Aufrufers nicht verlaesslich (gleiche Begruendung wie
    /// bei den Sheets in `WeinRootView`).
    let store: WeinStore

    /// Beendet die Serie. Der Aufrufer gibt sie mit, weil er den Zustand der Praesentation haelt —
    /// das ist der verlaessliche Weg. `nil` faellt auf `dismiss` zurueck, was hier ebenfalls
    /// funktioniert: diese Ansicht IST der Inhalt des `fullScreenCover`, also keine fremde
    /// Hierarchie mehr (daran war die alte Fassung gescheitert — dort sass der Knopf in einem
    /// eigenen UIHostingController, dessen `dismiss` ins Leere ging).
    var schliessen: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    /// Die Kamera gehoert dieser Ansicht: mit ihr aufgebaut, mit ihr gestoppt.
    @StateObject private var kamera = WeinKameraModell()

    /// Kurzer weisser Aufblitz beim Ausloesen — die einzige optische Rueckmeldung, die es ohne
    /// Bestaetigungsschirm gibt.
    @State private var blitz = false
    /// Kurzlebiger Klartext ueber dem Sucher (fehlgeschlagene Aufnahme, noch nicht bereit).
    @State private var hinweis: String?
    @State private var hinweisAufgabe: Task<Void, Never>?

    /// Ohne Kamera (Simulator, fehlende Hardware) hat die Serie keinen Sinn — der Bereich weicht
    /// dann auf die normale Erfassung aus, statt eine leere Kamera zu zeigen.
    static var kameraVerfuegbar: Bool { WeinKameraModell.kameraVorhanden }

    var body: some View {
        ZStack {
            // Grund fuer alle Zustaende: auch der Fehlerfall steht auf Schwarz, nicht auf der
            // Systemfarbe des Blattes.
            Color.black.ignoresSafeArea()

            inhalt

            // Aufblitz ueber dem Bild, aber UNTER den Knoepfen — und ohne Trefferflaeche, sonst
            // schluckt er genau die Beruehrung, die ihn ausgeloest hat.
            Color.white
                .opacity(blitz ? 0.85 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // BEWUSST ohne .ignoresSafeArea(): so und nur so respektieren Zaehler und Knoepfe die
            // Dynamic Island oben und den Home-Indikator unten.
            bedienung
        }
        .onAppear {
            // Die Closure faengt AUSDRUECKLICH nur `lauf` und `store` ein, nicht `self`.
            // `self` waere die Ansicht, und die haelt ueber `@StateObject` das Kameramodell —
            // das Modell haelt die Closure, die Closure hielte die Ansicht, die Ansicht das
            // Modell: ein geschlossener Ring, der nach jedem Durchgang eine komplette Kamera-Kette
            // samt Sitzung im Speicher liesse. Genau dann, wenn nebenher Bilder kodiert und
            // hochgeladen werden.
            kamera.onBild = { [lauf, store] bild in
                // Fehlschlaege meldet die Ansicht ueber `kamera.aufnahmeFehler` (siehe unten) —
                // dafuer braucht es hier keinen Zugriff auf ihren Zustand.
                guard let bild else { return }
                lauf.einreihen(store: store, image: bild)
            }
            kamera.starten()
        }
        // Fehlgeschlagene Aufnahme: die Kamera steht ja noch offen, ein Satz reicht und der Nutzer
        // loest einfach neu aus. Still verschwinden darf sie nicht.
        .onChange(of: kamera.aufnahmeFehler) { _, _ in
            zeige("Aufnahme fehlgeschlagen — bitte erneut auslösen")
        }
        .onDisappear {
            hinweisAufgabe?.cancel()
            // Sonst laeuft die Kamera weiter und die gruene Aufnahme-Anzeige bleibt an.
            kamera.stoppen()
        }
    }

    // ── Sucher bzw. Klartext statt schwarzem Bild ──

    @ViewBuilder
    private var inhalt: some View {
        switch kamera.zustand {
        case .startet, .bereit:
            WeinKameraVorschau(sitzung: kamera.sitzung)
                .ignoresSafeArea()
        case .keinZugriff:
            stoerung("Kamerazugriff ist deaktiviert — in den Einstellungen erlauben",
                     symbol: "camera.metering.unknown")
        case .fehler(let text):
            stoerung(text, symbol: "exclamationmark.triangle.fill")
        }
    }

    /// Fehlerbild. Es verdraengt den Sucher, NICHT die Bedienleiste — „Fertig" muss auch hier
    /// funktionieren, sonst sitzt der Nutzer in einem schwarzen Bildschirm fest.
    private func stoerung(_ text: String, symbol: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 44))
            Text(text)
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(28)
        .accessibilityIdentifier("wein-serie-stoerung")
    }

    // ── Bedienung ──

    private var bedienung: some View {
        VStack(spacing: 0) {
            fahne
            Spacer(minLength: 0)
            leiste
        }
        .padding(.top, 10)
        .padding(.bottom, 24)
    }

    /// Zaehler ueber dem Sucher. Fester dunkler Grund statt Material: der Untergrund ist ein
    /// Kamerabild und kann alles sein — nur so ist die Schrift in jedem Laden lesbar.
    private var fahne: some View {
        VStack(spacing: 3) {
            Text(lauf.stand)
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("wein-serie-zaehler")
            Text(hinweis ?? "Für jede Flasche auslösen — Fertig beendet die Serie")
                .font(.caption2)
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.black.opacity(0.55), in: Capsule())
        .allowsHitTesting(false)
    }

    /// Der Ausloeser sitzt mittig (Daumenweg wie in der Systemkamera), „Fertig" rechts daneben.
    /// Als ZStack, damit der Ausloeser wirklich in der Bildmitte bleibt und nicht von der Breite
    /// des Fertig-Knopfes verschoben wird.
    private var leiste: some View {
        ZStack {
            ausloeser
            HStack {
                Spacer()
                fertigKnopf
            }
        }
        .padding(.horizontal, 22)
    }

    /// Bewusst NIE gesperrt — auch nicht, waehrend Uploads laufen: die Uploads gehen nebenlaeufig
    /// raus, und genau das ist der Sinn der Serie. Ein Ausloeser, der auf das Netz wartet, waere
    /// langsamer als die Einzelerfassung. Auch im Stoerfall bleibt er stehen und bedienbar; er
    /// sagt dann, warum gerade nichts geht (ein grau abgesetzter Knopf erklaert nichts).
    private var ausloeser: some View {
        Button(action: ausloesenGedrueckt) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.9), lineWidth: 4).frame(width: 78, height: 78)
                Circle().fill(Color.white).frame(width: 64, height: 64)
            }
            .frame(width: 92, height: 92)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wein-serie-ausloeser")
        .accessibilityLabel("Flasche aufnehmen")
    }

    private var fertigKnopf: some View {
        Button(action: beenden) {
            Text("Fertig")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                // Mindestens 44 pt in beide Richtungen — darunter trifft im Laden niemand zuverlaessig.
                .frame(minWidth: 44, minHeight: 44)
                .background(Color.black.opacity(0.55), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wein-serie-schliessen")
    }

    // ── Aktionen ──

    private func ausloesenGedrueckt() {
        guard kamera.ausloesen() else {
            zeige("Kamera ist noch nicht bereit")
            return
        }
        aufblitzen()
    }

    /// Sichtbare Quittung fuer die Ausloesung. Der Haptik-Impuls kommt BEWUSST nicht hier, sondern
    /// aus `WeinSerienLauf.einreihen` — also in dem Moment, in dem das Bild wirklich vorliegt und
    /// in die Warteschlange geht. Zwei Impulse im Abstand von Sekundenbruchteilen lesen sich als
    /// Stottern, nicht als Bestaetigung.
    private func aufblitzen() {
        blitz = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            withAnimation(.easeOut(duration: 0.18)) { blitz = false }
        }
    }

    /// Serie beenden. Ueber die Closure des Aufrufers, sonst ueber `dismiss` (siehe `schliessen`).
    private func beenden() {
        if let aktion = schliessen { aktion() } else { dismiss() }
    }

    /// Kurzlebiger Hinweis in der Fahne; loest sich nach ein paar Sekunden von selbst wieder auf.
    private func zeige(_ text: String) {
        hinweis = text
        hinweisAufgabe?.cancel()
        hinweisAufgabe = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            hinweis = nil
        }
    }
}

// MARK: - Serie 2: Barcodes scannen

/// Barcode-Serie: ein Code nach dem anderen, ohne Zwischenschritt. Anders als der Einkaufs-Scan
/// wird hier NICHTS nachgeschlagen und nichts angezeigt — die Flasche geht direkt in die
/// Warteschlange, erkannt wird sie im Hintergrund.
struct WeinSerienBarcodeView: View {
    @ObservedObject var lauf: WeinSerienLauf
    let store: WeinStore

    @Environment(\.dismiss) private var dismiss

    /// Erzwingt eine frische Scanner-Instanz: der gemeinsame `BarcodeScannerView` liefert je
    /// Instanz genau EINEN Code (Muster aus `WeinEinkaufsScanView`).
    @State private var runde = 0
    /// Zeitpunkt je Code — dieselbe Flasche loest sonst mehrfach hintereinander aus.
    @State private var letzteScans: [String: Date] = [:]
    /// Geplanter Neustart des Scanners; wird beim Schliessen abgeraeumt.
    @State private var neustart: Task<Void, Never>?

    /// Entprellung: derselbe Code zaehlt erst nach dieser Zeit wieder als neue Flasche. Wer
    /// wirklich zwei gleiche Flaschen hat, scannt die zweite ein paar Sekunden spaeter — das ist
    /// seltener als das versehentliche Dauerfeuer, gegen das die Sperre schuetzt.
    private static let sperre: TimeInterval = 3

    private var tint: Color { Palette.colors(for: "wein").first ?? Theme.accent }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if BarcodeScannerView.isSupported {
                    BarcodeScannerView { code in gescannt(code) }
                        .id(runde)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .bottom) {
                            Text("Barcode anvisieren — eine Flasche nach der anderen")
                                .font(.footnote.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding()
                        }
                        .padding(.horizontal, 14)
                        .accessibilityIdentifier("wein-serie-scanner")
                } else {
                    ContentUnavailableView("Scanner nicht verfügbar", systemImage: "barcode.viewfinder",
                                           description: Text("Erfasse die Flaschen über die Kamera oder von Hand."))
                        .frame(maxHeight: .infinity)
                }

                Label(lauf.stand, systemImage: "tray.and.arrow.down.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.bottom, 6)
                    .accessibilityIdentifier("wein-serie-barcode-zaehler")
            }
            .background(Palette.gradient(for: "wein").opacity(0.05).ignoresSafeArea())
            .navigationTitle("Barcodes scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("wein-serie-barcode-schliessen")
                }
            }
            .onDisappear { neustart?.cancel() }
        }
    }

    /// Ein Code ist da: entprellen, einreihen, Scanner neu aufsetzen.
    private func gescannt(_ code: String) {
        let sauber = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sauber.isEmpty else {
            plane(neustartIn: 1.2)
            return
        }
        let jetzt = Date()
        if let zuletzt = letzteScans[sauber], jetzt.timeIntervalSince(zuletzt) < Self.sperre {
            // Dieselbe Flasche liegt noch im Bild. Nicht einreihen — und den Scanner erst wieder
            // aufsetzen, wenn die Sperre abgelaufen ist: ein sofortiger Neustart wuerde denselben
            // Code sofort wieder sehen und die Kamera in einer Dauerschleife neu aufbauen.
            plane(neustartIn: Self.sperre - jetzt.timeIntervalSince(zuletzt))
            return
        }
        letzteScans[sauber] = jetzt
        lauf.einreihen(store: store, ean: sauber)
        // Kurze Pause vor der naechsten Runde: Zeit, die Flasche zu wechseln.
        plane(neustartIn: 1.2)
    }

    /// Nach `sekunden` eine frische Scanner-Instanz aufsetzen. Ein bereits geplanter Neustart wird
    /// verworfen — sonst stapeln sich bei schnellem Scannen mehrere Neuaufbauten.
    private func plane(neustartIn sekunden: Double) {
        neustart?.cancel()
        let wartezeit = max(0.4, sekunden)
        // Ausdruecklich auf dem Hauptlauf: die Aufgabe setzt Ansichtszustand (`runde`), und der
        // gehoert dorthin.
        neustart = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(wartezeit * 1_000_000_000))
            guard !Task.isCancelled else { return }
            runde += 1
        }
    }
}
