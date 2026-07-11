import UIKit
import Vision
import FoundationModels

/// On-Device-Vorschlag des Lebensbereichs für ein Foto — privat, offline, kostenlos.
/// Pipeline: Vision liefert Bild-Labels → Apples Foundation Model (Text) wählt den
/// passendsten Bereichs-Schlüssel aus der (dynamischen) Liste. Rein additiv:
/// nicht verfügbar (< iPhone 15 Pro / Apple Intelligence aus) → nil, UI bleibt manuell.
@Generable
struct BereichGuess: Equatable {
    @Guide(description: "Der am besten passende Bereichs-Schlüssel aus der vorgegebenen Liste, sonst 'unbekannt'.")
    let bereich: String
}

enum PhotoBereichSuggester {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func suggest(image: UIImage, note: String, bereiche: [Lebensbereich]) async -> String? {
        guard isAvailable, !bereiche.isEmpty else { return nil }

        let labels = await imageLabels(image)
        let contextParts = [
            labels.isEmpty ? nil : "Bilderkennung: \(labels.joined(separator: ", "))",
            note.isEmpty ? nil : "Notiz: \(note)",
        ].compactMap { $0 }
        guard !contextParts.isEmpty else { return nil }

        let list = bereiche.map { "\($0.key) (\($0.titel))" }.joined(separator: ", ")
        let prompt = """
        Ordne ein Familienfoto genau einem Lebensbereich zu.
        Verfügbare Bereiche als Schlüssel: \(list).
        Kontext: \(contextParts.joined(separator: ". ")).
        Antworte nur mit dem passendsten Schlüssel aus der Liste (exakt so geschrieben) oder 'unbekannt'.
        """

        do {
            let session = LanguageModelSession {
                "Du ordnest Familienfotos knapp und präzise einem Lebensbereich zu."
            }
            let result = try await session.respond(to: prompt, generating: BereichGuess.self)
            let guess = result.content.bereich.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return bereiche.first(where: { $0.key.lowercased() == guess })?.key
        } catch {
            return nil
        }
    }

    /// Vision-Bildklassifikation (off-main). Liefert die stärksten Labels.
    private static func imageLabels(_ image: UIImage) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                try? handler.perform([request])
                let results = (request.results ?? [])
                    .filter { $0.confidence > 0.15 }
                    .prefix(5)
                    .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
                cont.resume(returning: Array(results))
            }
        }
    }
}
