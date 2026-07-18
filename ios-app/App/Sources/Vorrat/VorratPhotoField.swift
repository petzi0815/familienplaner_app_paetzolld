import SwiftUI
import UIKit

/// Foto-Erfassung für Lebensmittel: Kamera oder Mediathek → Vorschau + Entfernen.
/// Bindet ein `UIImage?`; das Hochladen (→ storage_key/bild_pfad) macht der aufrufende Save-Flow.
struct VorratPhotoField: View {
    @Binding var image: UIImage?
    @State private var source: ImageSource?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let img = image {
                HStack(spacing: 12) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Button(role: .destructive) { image = nil } label: {
                        Label("Entfernen", systemImage: "trash")
                    }
                    .font(.subheadline)
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 12) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { source = ImageSource(.camera) } label: {
                        Label("Foto aufnehmen", systemImage: "camera.fill")
                    }
                    .accessibilityIdentifier("vorrat-photo-camera")
                }
                Button { source = ImageSource(.photoLibrary) } label: {
                    Label(image == nil ? "Mediathek" : "Ändern", systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("vorrat-photo-library")
                Spacer(minLength: 0)
            }
            .font(.subheadline)
        }
        .sheet(item: $source) { s in
            ImagePicker(sourceType: s.type) { image = $0 }
        }
    }
}
