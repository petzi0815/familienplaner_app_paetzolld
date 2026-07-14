import UIKit

/// Gemeinsames Toast-/Fehler-Verhalten für Bereichs-Stores. Entfernt die pro-Store duplizierte
/// notify/errText-Boilerplate: der Store hält nur noch `message`/`messageIsError` (@Published),
/// die Standard-Implementierungen kommen aus diesem Protokoll.
///
/// Verwendung: `final class XyzStore: ObservableObject, NotifiableStore { @Published var message ...;
/// @Published var messageIsError = false }` — danach stehen `notify(_:error:)` und `errText(_:)` bereit.
@MainActor
protocol NotifiableStore: AnyObject {
    var message: String? { get set }
    var messageIsError: Bool { get set }
}

@MainActor
extension NotifiableStore {
    /// Setzt den Toast UND gibt zentrales haptisches Feedback (Erfolg = leichter Tap, Fehler = Warnung)
    /// — greift dadurch für ALLE Bereiche (Speichern/Löschen/Umschalten laufen über notify).
    func notify(_ text: String, error: Bool = false) {
        message = text; messageIsError = error
        if error { UINotificationFeedbackGenerator().notificationOccurred(.error) }
        else { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }
    func errText(_ e: Error) -> String { (e as? APIError)?.errorDescription ?? "Fehler" }
}
