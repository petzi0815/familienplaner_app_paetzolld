import AVFoundation
import SwiftUI
import UIKit

// Kamera der Foto-Serie — AVFoundation statt UIImagePickerController.
//
// WARUM ein eigener Aufbau: die erste Fassung lief ueber UIImagePickerController mit
// abgeschalteter Standardsteuerung und einer eigenen Ebene als `cameraOverlayView`. Am Geraet war
// das dreifach kaputt, und alle drei Fehler folgen direkt aus dieser Bauart:
//
//   * Die Vorschau des Bildwaehlers ist fest 4:3. Auf einem 19,5:9-Bildschirm fuellt sie die
//     oberen zwei Drittel — darunter bleibt alles schwarz.
//   * Die Ebene haengt in einem separaten UIHostingController AUSSERHALB der SwiftUI-Hierarchie.
//     Deren Knoepfe reagieren nicht verlaesslich — „Fertig" schloss den Dialog nicht.
//   * Die Ebene sitzt im Koordinatensystem des Waehlers und kennt die sicheren Bereiche des
//     Geraets nicht: der Zaehler lag unter der Dynamic Island und war dort abgeschnitten.
//
// Mit AVFoundation gehoert der Sucher der App: er fuellt den Bildschirm (`resizeAspectFill`), die
// Bedienelemente sind gewoehnliche SwiftUI-Ansichten in DERSELBEN Hierarchie, und die sicheren
// Bereiche gelten damit automatisch.

// MARK: - Modell

/// Kapselt Sitzung und Foto-Ausgang: Berechtigung klaeren, aufbauen, starten, ausloesen, stoppen.
///
/// Aufbau und `startRunning()`/`stopRunning()` laufen ausschliesslich auf einer EIGENEN seriellen
/// Warteschlange. Auf dem Hauptlauf brauchen sie je nach Geraet mehrere hundert Millisekunden und
/// frieren die Oberflaeche sichtbar ein — samt des Fertig-Knopfes, der dann genauso wenig reagiert
/// wie in der alten Fassung. Der VEROEFFENTLICHTE Zustand geht dagegen immer ueber den Hauptlauf,
/// weil er die Ansicht treibt (`setze(_:)`).
final class WeinKameraModell: ObservableObject {

    /// Was der Nutzer sehen soll. Der Fehlerfall traegt seinen Klartext gleich mit — ein schwarzes
    /// Bild ohne Erklaerung ist die schlechteste aller Antworten.
    enum Zustand: Equatable {
        /// Berechtigung/Aufbau laufen noch.
        case startet
        /// Sucher lebt, Ausloesen moeglich.
        case bereit
        /// Zugriff verweigert (oder von der Geraeteverwaltung gesperrt).
        case keinZugriff
        /// Keine Kamera vorhanden oder die Sitzung liess sich nicht bauen.
        case fehler(String)
    }

    @Published private(set) var zustand: Zustand = .startet

    /// Wird nach JEDER Ausloesung auf dem Hauptlauf gerufen — mit dem Bild, oder mit `nil`, wenn
    /// die Aufnahme fehlschlug. Der Aufrufer muss auch den `nil`-Fall behandeln: eine stumm
    /// verschluckte Ausloesung waere genau der Verlust, den die Serie ausschliesst.
    var onBild: ((UIImage?) -> Void)?

    /// Zaehlt fehlgeschlagene Aufnahmen. Die Ansicht beobachtet die Zahl und zeigt dann ihren
    /// Klartext — so kommt sie ohne eine Closure aus, die `self` einfaengt (siehe `onBild`
    /// in `WeinSerienFotoView`: dort entstuende sonst ein Zyklus, der die ganze Kamera-Kette
    /// am Leben haelt).
    @Published private(set) var aufnahmeFehler = 0

    /// Die Sitzung. Ausser der Vorschau (die sie nur an ihre Ebene haengt) fasst sie niemand vom
    /// Hauptlauf aus an — verwaltet wird sie auf `warteschlange`.
    let sitzung = AVCaptureSession()

    private let fotoAusgabe = AVCapturePhotoOutput()
    private let warteschlange = DispatchQueue(label: "app.yagemi.familienplaner.wein-kamera")

    /// Nur auf `warteschlange` gelesen/geschrieben: der Aufbau darf sich nicht wiederholen (sonst
    /// haengt beim zweiten Erscheinen ein zweiter Eingang an derselben Sitzung).
    private var aufgebaut = false

    /// Marke des Stoerungs-Beobachters (siehe `beobachteStoerungen`) — zum Abmelden in `deinit`.
    private var stoerungsBeobachter: NSObjectProtocol?

    /// Laufende Aufnahmen. `capturePhoto(with:delegate:)` haelt den Delegate NICHT fest — ohne
    /// diese Ablage waere er vor dem Ergebnis freigegeben und das Bild verloren. Wird nur auf dem
    /// Hauptlauf angefasst: eingetragen beim Ausloesen (kommt aus der Ansicht), ausgetragen im
    /// Rueckruf, der sich dafuer eigens auf den Hauptlauf schiebt.
    private var offeneAufnahmen: [UUID: WeinFotoAusloeser] = [:]

    /// Ist ueberhaupt eine Kamera verbaut? (Im Simulator: nein.) Ueber die BERECHTIGUNG sagt das
    /// nichts — die klaert `starten()`.
    static var kameraVorhanden: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
            || AVCaptureDevice.default(for: .video) != nil
    }

    // MARK: Start / Stop

    /// Berechtigung klaeren und die Sitzung starten. Mehrfach aufrufbar — die Ansicht ruft es bei
    /// jedem Erscheinen, und der Aufbau selbst laeuft nur einmal.
    func starten() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            aufbauenUndStarten()
        case .notDetermined:
            // Der Rueckruf kommt auf irgendeinem Faden; `aufbauenUndStarten` schiebt selbst auf
            // die eigene Warteschlange, das ist also unkritisch.
            AVCaptureDevice.requestAccess(for: .video) { [weak self] erlaubt in
                guard let self else { return }
                if erlaubt { self.aufbauenUndStarten() } else { self.setze(.keinZugriff) }
            }
        default:
            // .denied und .restricted enden beide hier: kein Bild, aber ein Satz dazu.
            setze(.keinZugriff)
        }
    }

    deinit {
        if let stoerungsBeobachter { NotificationCenter.default.removeObserver(stoerungsBeobachter) }
        // Sicherheitsnetz: normalerweise stoppt die Ansicht die Sitzung beim Verschwinden. Faellt
        // das Modell aus einem anderen Grund weg, darf die Kamera trotzdem nicht weiterlaufen.
        if sitzung.isRunning { sitzung.stopRunning() }
    }

    /// Sitzung anhalten. Ohne das laeuft die Kamera nach dem Schliessen weiter und die gruene
    /// Aufnahme-Anzeige des Systems bleibt an — fuer den Nutzer sieht das aus wie eine App, die
    /// heimlich mitfilmt.
    func stoppen() {
        warteschlange.async { [weak self] in
            guard let self, self.sitzung.isRunning else { return }
            self.sitzung.stopRunning()
        }
    }

    private func aufbauenUndStarten() {
        warteschlange.async { [weak self] in
            guard let self else { return }
            if !self.aufgebaut {
                if let grund = self.aufbauen() {
                    self.setze(.fehler(grund))
                    return
                }
                self.aufgebaut = true
                self.beobachteStoerungen()
            }
            if !self.sitzung.isRunning { self.sitzung.startRunning() }
            // NICHT einfach `.bereit` behaupten: `startRunning()` hat keinen Rueckgabewert und
            // meldet einen Fehlschlag ausschliesslich ueber `AVCaptureSessionRuntimeError`. Wer
            // hier blind `.bereit` setzt, zeigt einen bedienbaren Ausloeser ueber einer stehenden
            // Sitzung — und `capturePhoto` auf einer stehenden Sitzung beendet die App.
            self.setze(self.sitzung.isRunning
                       ? .bereit
                       : .fehler("Die Kamera ließ sich nicht starten. Bitte die App neu öffnen."))
        }
    }

    /// Bricht die Sitzung im Betrieb weg (Anruf, Media-Dienst startet neu, andere App greift zu),
    /// erfaehrt man das NUR ueber diese Meldung. Ohne sie bliebe der Zustand auf `.bereit`, der
    /// Sucher zeigte ein Standbild und jede weitere Ausloesung liefe ins Leere.
    private func beobachteStoerungen() {
        // Die Marke MUSS aufbewahrt und in `deinit` wieder abgemeldet werden: block-basierte
        // Beobachter raeumt die Benachrichtigungszentrale — anders als selektor-basierte — NICHT
        // von selbst ab. Sonst bliebe je Serien-Durchgang ein toter Beobachter zurueck.
        // Zugriff nur auf `warteschlange`, wie `aufgebaut`.
        stoerungsBeobachter = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionRuntimeError, object: sitzung, queue: .main,
        ) { [weak self] hinweis in
            guard let self else { return }
            let grund = (hinweis.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription
            self.setze(.fehler(grund ?? "Die Kamera wurde unterbrochen."))
            // Ein Neustartversuch ist billig und rettet den haeufigsten Fall (kurze Unterbrechung
            // durch eine andere App). Gelingt er nicht, bleibt der Klartext oben stehen.
            self.warteschlange.async { [weak self] in
                guard let self, !self.sitzung.isRunning else { return }
                self.sitzung.startRunning()
                if self.sitzung.isRunning { self.setze(.bereit) }
            }
        }
    }

    /// Eingang (Rueckkamera) und Foto-Ausgang zusammenstecken. Gibt im Fehlerfall den Klartext
    /// zurueck, der dann auf dem Schirm steht. Laeuft NUR auf `warteschlange`.
    private func aufbauen() -> String? {
        sitzung.beginConfiguration()
        sitzung.sessionPreset = .photo

        // Rueckkamera zuerst — ein Etikett fotografiert niemand mit der Frontkamera. Der zweite
        // Versuch ohne Positionsvorgabe fangt Geraete ohne Weitwinkel hinten ab.
        guard let geraet = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video) else {
            sitzung.commitConfiguration()
            return "Keine Kamera gefunden — erfasse die Flasche über die Erfassung."
        }

        do {
            let eingang = try AVCaptureDeviceInput(device: geraet)
            guard sitzung.canAddInput(eingang) else {
                sitzung.commitConfiguration()
                return "Die Kamera lässt sich nicht öffnen."
            }
            sitzung.addInput(eingang)
        } catch {
            sitzung.commitConfiguration()
            return "Die Kamera lässt sich nicht öffnen."
        }

        guard sitzung.canAddOutput(fotoAusgabe) else {
            sitzung.commitConfiguration()
            return "Die Kamera lässt sich nicht öffnen."
        }
        sitzung.addOutput(fotoAusgabe)

        sitzung.commitConfiguration()
        return nil
    }

    // MARK: Ausloesen

    /// Ein Bild machen. Gibt `false` zurueck, wenn die Sitzung (noch) nicht laeuft — die Ansicht
    /// sagt dann Bescheid, statt den Ausloeser zu sperren. Wird vom Hauptlauf gerufen.
    ///
    /// Die Einstellungen werden BEWUSST je Aufnahme neu gebaut: ein `AVCapturePhotoSettings`-Objekt
    /// darf laut Apple nur ein einziges Mal verwendet werden, ein zweiter Lauf damit beendet die App.
    /// Vorgaben werden keine gesetzt — insbesondere keine Qualitaetsstufe, die ueber der des
    /// Ausgangs liegt (auch das beendet die App).
    @discardableResult
    func ausloesen() -> Bool {
        // Zweite, harte Absicherung neben dem Zustand: `capturePhoto` auf einer stehenden Sitzung
        // oder ohne aktive Videoverbindung wirft eine ObjC-Ausnahme, die Swift NICHT fangen kann —
        // das beendet die App mitten in der Serie samt der noch nicht gemeldeten Bilanz.
        guard zustand == .bereit,
              sitzung.isRunning,
              fotoAusgabe.connection(with: .video)?.isActive == true else { return false }
        let einstellungen = AVCapturePhotoSettings()
        let ausloeser = WeinFotoAusloeser { [weak self] kennung, bild in
            // Der Rueckruf kommt nicht vom Hauptlauf — der Zustand der Ansicht schon.
            DispatchQueue.main.async {
                guard let self else { return }
                self.offeneAufnahmen.removeValue(forKey: kennung)
                if bild == nil { self.aufnahmeFehler += 1 }
                self.onBild?(bild)
            }
        }
        offeneAufnahmen[ausloeser.kennung] = ausloeser
        // Auf der Sitzungs-Warteschlange: sie ist seriell, damit steht die Aufnahme garantiert
        // hinter einem eventuell noch laufenden `startRunning()`.
        warteschlange.async { [weak self] in
            self?.fotoAusgabe.capturePhoto(with: einstellungen, delegate: ausloeser)
        }
        return true
    }

    /// Zustand veroeffentlichen — immer ueber den Hauptlauf, weil er die Ansicht treibt.
    private func setze(_ neu: Zustand) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.zustand != neu else { return }
            self.zustand = neu
        }
    }
}

// MARK: - Delegate einer einzelnen Aufnahme

/// Ein Delegate je Bild. `AVCapturePhotoOutput` haelt ihn nicht fest, deshalb liegt er solange in
/// `WeinKameraModell.offeneAufnahmen` und meldet sich ueber seine `kennung` selbst wieder ab.
private final class WeinFotoAusloeser: NSObject, AVCapturePhotoCaptureDelegate {
    let kennung = UUID()
    private let fertig: (UUID, UIImage?) -> Void

    init(fertig: @escaping (UUID, UIImage?) -> Void) {
        self.fertig = fertig
    }

    /// Die einzige Methode, die diese Serie braucht: fertig verarbeitetes Foto (oder Fehler).
    /// Die Daten sind JPEG mit EXIF-Ausrichtung; `UIImage(data:)` uebernimmt sie, und das spaetere
    /// Verkleinern in `jpegForUpload` zeichnet dadurch richtig herum.
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil,
              let daten = photo.fileDataRepresentation(),
              let bild = UIImage(data: daten) else {
            fertig(kennung, nil)
            return
        }
        fertig(kennung, bild)
    }
}

// MARK: - Sucher

/// Die View, deren Hintergrund-Ebene der Vorschau-Layer IST.
///
/// `layerClass` zu ueberschreiben ist hier der entscheidende Punkt: die Backing-Ebene wird von
/// UIKit bei jedem Layout automatisch auf die Groesse der View gezogen. Haengt man den Layer
/// stattdessen als Sublayer ein, behaelt er die Groesse des ERSTEN Layouts — auf dem Geraet bleibt
/// das Bild dann in einer Ecke stehen, und genau solche Groessen-Ueberraschungen waren der Grund
/// fuer das schwarze untere Drittel der alten Fassung.
final class WeinKameraVorschauView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    /// Bequemer Zugriff — der Cast kann nicht fehlschlagen, `layerClass` gibt den Typ vor.
    var vorschauLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

/// SwiftUI-Huelle um den Sucher.
struct WeinKameraVorschau: UIViewRepresentable {
    let sitzung: AVCaptureSession

    func makeUIView(context: Context) -> WeinKameraVorschauView {
        let view = WeinKameraVorschauView()
        // Schwarz statt Systemfarbe: bis das erste Einzelbild da ist, soll nichts aufblitzen.
        view.backgroundColor = .black
        // Fuellend statt eingepasst — sonst waeren wir wieder bei den schwarzen Balken.
        view.vorschauLayer.videoGravity = .resizeAspectFill
        view.vorschauLayer.session = sitzung
        return view
    }

    func updateUIView(_ view: WeinKameraVorschauView, context: Context) {
        // Die Sitzung wechselt waehrend einer Serie nicht; die Zuweisung bleibt trotzdem
        // idempotent, damit ein Neuaufbau der Ansicht keinen leeren Sucher hinterlaesst.
        if view.vorschauLayer.session !== sitzung { view.vorschauLayer.session = sitzung }
    }
}
