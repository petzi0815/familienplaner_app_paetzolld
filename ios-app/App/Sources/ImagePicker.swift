import SwiftUI
import UIKit

/// UIImagePickerController als SwiftUI-Wrapper (Kamera ODER Fotothek via sourceType).
///
/// Fuer EINZELNE Aufnahmen — Foto machen, Blatt schliessen. Eine Kamera im Dauerbetrieb (die
/// Foto-Serie im Wein-Bereich) laesst sich damit NICHT bauen: dafuer muesste man die
/// Standardsteuerung abschalten und eine eigene Ebene als `cameraOverlayView` einhaengen, und
/// deren Vorschau ist fest 4:3, ihre Knoepfe liegen ausserhalb der SwiftUI-Hierarchie und die
/// sicheren Bereiche des Geraets kennt sie nicht. Der richtige Weg dafuer steht in
/// `Wein/WeinKamera.swift` (AVFoundation).
struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType = .photoLibrary
    var onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = Self.verfuegbareQuelle(sourceType)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

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

        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPick(image) }
            parent.dismiss()
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
