import ActivityKit
import AppIntents
import Foundation
import WidgetKit

/// Interaktive Intents für Widgets und Live Activities.
///
/// Die Datei liegt in `Shared/` und wird damit in **beide** Targets (App + Widget-Extension)
/// kompiliert — nötig, weil `TerminAckIntent` ein `LiveActivityIntent` ist: der Button wird im
/// Widget-/Live-Activity-Prozess *gerendert*, `perform()` führt das System aber im **App-Prozess**
/// aus. Nur dort darf ActivityKit die laufende Activity aktualisieren.
///
/// Erlaubt sind hier ausschließlich Frameworks, die es in beiden Targets gibt
/// (Foundation/WidgetKit/AppIntents/ActivityKit) plus `SharedStore`/`TerminAck` aus `Shared/`.
/// **Kein** Zugriff auf App-Typen (AppState/APIClient) — die gibt es in der Extension nicht.
enum TerminAckAction: String {
    /// Gelesen quittiert (setzt `read=1`, `ack_at`).
    case gelesen
    /// Zusätzlich `termine.status='erledigt'` (geteilt für die ganze Familie).
    case erledigt
    /// Keine weiteren Erinnerungen für diesen Termin (`muted=1, notify=0`).
    case stumm
    /// Stummschaltung aufheben.
    case laut

    /// Tolerantes Mapping — unbekannte Werte quittieren nur „gelesen“ statt zu scheitern.
    init(raw: String) {
        self = TerminAckAction(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .gelesen
    }

    /// Gegenstück im gemeinsamen Ack-Client (gleiche Roh-Werte, harter Vertrag mit der Route).
    var ack: TerminAck.Action { TerminAck.Action(rawValue: rawValue) ?? .gelesen }

    var buttonTitle: String {
        switch self {
        case .gelesen: return "Gelesen"
        case .erledigt: return "Erledigt"
        case .stumm: return "Nicht mehr erinnern"
        case .laut: return "Wieder erinnern"
        }
    }

    var systemImage: String {
        switch self {
        case .gelesen: return "checkmark.circle.fill"
        case .erledigt: return "checkmark.seal.fill"
        case .stumm: return "bell.slash.fill"
        case .laut: return "bell.fill"
        }
    }
}

/// Lokale Sofort-Rückmeldung an laufende Live Activities.
///
/// Liegt bewusst in `Shared/`, damit der Intent (App-Prozess, aber in beiden Targets kompiliert)
/// und der `LiveActivityManager` der App exakt dieselbe Logik nutzen. ActivityKit ist in beiden
/// Targets verfügbar; wirksam sind die Aufrufe im App-Prozess — genau dort läuft
/// `LiveActivityIntent.perform()`.
enum TerminLiveActivity {
    private static func running(terminId: Int) -> [Activity<TerminActivityAttributes>] {
        Activity<TerminActivityAttributes>.activities.filter { $0.attributes.terminId == terminId }
    }

    /// Status auf "quittiert" setzen und den Quittierenden vermerken.
    static func markAcked(terminId: Int, owner: String? = nil) async {
        let me = owner ?? SharedStore.owner ?? "ich"
        for activity in running(terminId: terminId) {
            var state = activity.content.state
            state.status = "quittiert"
            if !state.ackedBy.contains(me) { state.ackedBy.append(me) }
            await activity.update(ActivityContent(state: state, staleDate: activity.content.staleDate))
        }
    }

    /// Activity beenden (nach "erledigt"/"stumm" ist sie gegenstandslos).
    static func end(terminId: Int) async {
        for activity in running(terminId: terminId) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

/// Quittiert einen Termin direkt aus Widget / Live Activity / Dynamic Island heraus —
/// ohne die App zu öffnen. Ruft `POST /api/termine/{id}/ack` mit dem App-Group-Key.
///
/// `LiveActivityIntent` (statt reinem `AppIntent`): nur so läuft `perform()` im App-Prozess und
/// darf die Live Activity anfassen. Sonst bliebe der Quittieren-Button bis zum nächsten
/// Server-Push (bis zu 15 min) unverändert stehen, weil `WidgetCenter.reloadAllTimelines()` zwar
/// WidgetKit-Timelines, aber **nicht** den `ContentState` einer Activity aktualisiert.
struct TerminAckIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Termin quittieren"
    static var description = IntentDescription("Markiert einen Termin als gelesen, erledigt oder stumm.")
    /// Läuft im Hintergrund — die App wird bewusst NICHT in den Vordergrund geholt.
    static var openAppWhenRun: Bool = false
    /// Kein Eintrag in der Kurzbefehle-App (rein interner Button-Intent).
    static var isDiscoverable: Bool = false

    @Parameter(title: "Termin")
    var terminId: Int

    /// "gelesen" | "erledigt" | "stumm" | "laut" (harter Vertrag mit der Ack-Route).
    @Parameter(title: "Aktion")
    var action: String

    // AppIntent verlangt init(); die Convenience-Variante ist der Aufruf aus den Views.
    init() {
        self.terminId = 0
        self.action = TerminAckAction.gelesen.rawValue
    }

    init(terminId: Int, action: TerminAckAction = .gelesen) {
        self.terminId = terminId
        self.action = action.rawValue
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let act = TerminAckAction(raw: action)
        guard terminId > 0 else { return .result(dialog: "Termin nicht gefunden.") }

        // Kurzes Timeout: der Button darf den Sperrbildschirm nicht sekundenlang blockieren.
        // `TerminAck.send` wertet den Statuscode aus — ein 401/500 gilt NICHT als Erfolg.
        guard await TerminAck.send(terminId: terminId, action: act.ack, timeout: 5) else {
            // Ehrlich bleiben: nichts neu laden (der Button darf nicht kurz als quittiert
            // erscheinen und dann zurückspringen), sondern den Fehlschlag melden.
            return .result(dialog: "Quittieren fehlgeschlagen – bitte in der App erneut versuchen.")
        }

        // Sofort-Rückmeldung in der Live Activity (der Server-Push kommt zusätzlich, aber später).
        switch act {
        case .gelesen: await TerminLiveActivity.markAcked(terminId: terminId)
        case .erledigt, .stumm: await TerminLiveActivity.end(terminId: terminId)
        case .laut: break
        }
        // Timeline neu ziehen, damit „gelesen“/„stumm“ auch in den Widgets sichtbar wird.
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Gespeichert.")
    }
}
