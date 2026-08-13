import SwiftUI
import UIKit

/// Die Knoepfe, die eine Serienaufnahme braucht — der Aufrufer baut sie in seine eigene Ebene ein
/// und bestimmt damit Aussehen, Beschriftung und Bezeichner. `ausloesen` macht ein Bild (der Sucher
/// bleibt danach stehen), `fertig` schliesst die Kamera und beendet die Serie.
struct ImagePickerSerie {
    let ausloesen: () -> Void
    let fertig: () -> Void
}

/// UIImagePickerController als SwiftUI-Wrapper (Kamera ODER Fotothek via sourceType).
struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType = .photoLibrary

    /// Serienmodus — gesetzt heisst: eigene Bedienebene ueber dem Sucher, und die Kamera schliesst
    /// sich nach dem Ausloesen NICHT (Flasche fuer Flasche, ohne jedes Mal neu einzusteigen).
    ///
    /// Die eigene Ebene ist hier kein Schmuck, sondern die Voraussetzung: mit der STANDARD-Steuerung
    /// (`showsCameraControls = true`) schiebt UIImagePickerController nach jedem Ausloesen den
    /// Bestaetigungsschirm („Erneut aufnehmen" / „Foto verwenden") davor. Der Delegate feuert erst
    /// beim Bestaetigen — und ohne `dismiss()` bliebe genau dieser Schirm stehen, der Sucher kaeme
    /// nie zurueck. Deshalb wird im Serienmodus die Standardsteuerung abgeschaltet und die eigene
    /// Ebene als `cameraOverlayView` eingehaengt: kein Bestaetigungsschirm, das Bild ist mit dem
    /// Ausloesen fertig, der Sucher steht sofort wieder bereit.
    ///
    /// `nil` (der Default) haelt alle bestehenden Aufrufstellen unveraendert: Standardsteuerung,
    /// Bestaetigungsschirm, Schliessen nach der Auswahl — genau wie bisher.
    /// (Das `= nil` steht ausdruecklich da: nur ein AUSGESCHRIEBENER Vorgabewert landet auch im
    /// erzeugten Initialisierer — sonst muessten alle bestehenden Aufrufstellen ihn mitgeben.)
    var serienBedienung: ((ImagePickerSerie) -> AnyView)? = nil

    var onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = Self.verfuegbareQuelle(sourceType)
        picker.delegate = context.coordinator
        // Die eigene Ebene gibt es nur ueber der echten Kamera — die Fotothek hat keinen Sucher und
        // keinen Ausloeser, ueber den sich eine Serie fuehren liesse.
        if serienBedienung != nil, picker.sourceType == .camera {
            context.coordinator.bedienebeneEinhaengen(in: picker)
        }
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {
        context.coordinator.bedienebeneAktualisieren(in: controller, bauen: serienBedienung)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Faellt auf die Fotothek zurueck, wenn die gewuenschte Quelle fehlt (Simulator ohne Kamera):
    /// eine nicht verfuegbare Quelle zu setzen, beendet die App — ein Bildwaehler ohne Kamera ist
    /// die deutlich bessere Antwort als ein Absturz.
    private static func verfuegbareQuelle(
        _ gewuenscht: UIImagePickerController.SourceType
    ) -> UIImagePickerController.SourceType {
        UIImagePickerController.isSourceTypeAvailable(gewuenscht) ? gewuenscht : .photoLibrary
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker

        /// Der Hosting-Controller der Bedienebene — hier STARK gehalten. `cameraOverlayView` haelt
        /// nur die View, nicht ihren Controller: ohne diese Referenz wird er freigegeben, und die
        /// Ebene ist tot (keine Knopfdruecke, kein Aktualisieren des Zaehlers mehr).
        private var bedienebene: UIHostingController<AnyView>?
        /// Die Knoepfe der laufenden Serie — zum Neubauen der Ebene bei Aktualisierungen.
        private var steuerung: ImagePickerSerie?
        /// Laeuft wirklich eine Serie? Nur dann bleibt die Kamera nach dem Ausloesen stehen. Fehlt
        /// die Kamera (Simulator), wurde keine Ebene eingehaengt — dann verhaelt sich der Waehler
        /// wie ueberall sonst und schliesst nach dem Bild, statt sich nicht mehr schliessen zu lassen.
        private var serieAktiv = false

        init(_ parent: ImagePicker) { self.parent = parent }

        /// Standardsteuerung abschalten und die eigene Ebene ueber den Sucher legen.
        func bedienebeneEinhaengen(in picker: UIImagePickerController) {
            guard let bauen = parent.serienBedienung else { return }
            picker.showsCameraControls = false
            // `takePicture()` wirkt ausschliesslich ohne Standardsteuerung — genau deshalb steht die
            // Zeile darueber. Beide Bezuege schwach: die Ebene haengt am Waehler, der Waehler wird
            // von SwiftUI gehalten, und der Ausloeser darf ihn nicht am Leben halten.
            let knoepfe = ImagePickerSerie(
                ausloesen: { [weak picker] in picker?.takePicture() },
                fertig: { [weak self] in self?.parent.dismiss() }
            )
            let hosting = UIHostingController(rootView: bauen(knoepfe))
            // Ohne durchsichtigen Hintergrund verdeckt die Ebene das Kamerabild — der
            // Hosting-Controller malt sonst die Systemfarbe hinter seine Ansicht.
            hosting.view.backgroundColor = .clear
            hosting.view.isOpaque = false
            hosting.view.frame = picker.view.bounds
            hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            picker.cameraOverlayView = hosting.view
            steuerung = knoepfe
            bedienebene = hosting
            serieAktiv = true
        }

        /// Ebene nachziehen: neuer Inhalt (Zaehlerstand) und, falls sich die Groesse erst nach dem
        /// Anlegen ergeben hat, die passende Flaeche.
        func bedienebeneAktualisieren(in picker: UIImagePickerController,
                                      bauen: ((ImagePickerSerie) -> AnyView)?) {
            guard let hosting = bedienebene, let knoepfe = steuerung, let bauen else { return }
            hosting.rootView = bauen(knoepfe)
            let flaeche = picker.view.bounds
            if flaeche.width > 0, flaeche.height > 0, hosting.view.frame != flaeche {
                hosting.view.frame = flaeche
            }
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPick(image) }
            // In der Serie bleibt der Sucher bewusst stehen: ohne Standardsteuerung gibt es keinen
            // Bestaetigungsschirm, das Bild ist mit dem Ausloesen fertig. Geschlossen wird ueber
            // „Fertig" in der eigenen Bedienebene.
            if !serieAktiv { parent.dismiss() }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// Identifiable-Wrapper für `.sheet(item:)`.
struct ImageSource: Identifiable {
    let id = UUID()
    let type: UIImagePickerController.SourceType
    init(_ type: UIImagePickerController.SourceType) { self.type = type }
}

extension UIImage {
    /// JPEG, herunterskaliert auf maximale Kantenlänge — hält Uploads klein.
    func jpegForUpload(maxEdge: CGFloat = 2000, quality: CGFloat = 0.8) -> Data? {
        let longest = max(size.width, size.height)
        let scale = longest > maxEdge ? maxEdge / longest : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let scaled = renderer.image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return scaled.jpegData(compressionQuality: quality)
    }
}
