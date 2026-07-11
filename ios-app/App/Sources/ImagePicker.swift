import SwiftUI
import UIKit

/// UIImagePickerController als SwiftUI-Wrapper (Kamera ODER Fotothek via sourceType).
struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType = .photoLibrary
    var onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

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
