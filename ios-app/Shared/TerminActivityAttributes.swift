import ActivityKit
import Foundation

/// Live Activity für einen Termin (Sperrbildschirm + Dynamic Island).
///
/// **Harter Vertrag mit dem Backend** (`server/push/apns.ts::sendLiveActivity`):
/// - Der Typname `TerminActivityAttributes` wandert 1:1 ins APNs-Feld `attributes-type`.
/// - ActivityKit decodiert `content-state`/`attributes` mit dem Swift-Codable-Default →
///   die **Property-Namen hier sind maßgeblich** (camelCase, KEIN snake_case).
/// - Zeitpunkte bewusst als `Double` (Unix-Epoch-Sekunden) statt `Date`: die Standard-
///   Date-Strategie wäre das Apple-Reference-Date (2001) — eine klassische Fehlerquelle
///   zwischen Node und Swift. Epoch-Sekunden sind eindeutig; `Date` gibt es als Computed.
struct TerminActivityAttributes: ActivityAttributes {
    /// Dynamischer Teil — wird per Push aktualisiert.
    struct ContentState: Codable, Hashable {
        var title: String
        /// Person/Kategorie („Samu", „Zahnarzt").
        var subtitle: String?
        var location: String?
        /// Beginn als Unix-Epoch-Sekunden.
        var startAtEpoch: Double
        /// Ende als Unix-Epoch-Sekunden (nil = keine Endzeit hinterlegt).
        var endAtEpoch: Double?
        var allDay: Bool
        /// "bevorstehend" | "laeuft" | "quittiert" | "vorbei"
        var status: String
        var emoji: String
        /// Wer hat bereits quittiert (`["lars"]`).
        var ackedBy: [String]

        var startAt: Date { Date(timeIntervalSince1970: startAtEpoch) }
        var endAt: Date? { endAtEpoch.map { Date(timeIntervalSince1970: $0) } }
        var isRunning: Bool { status == "laeuft" }
        /// Hat überhaupt jemand quittiert (für „Quittiert von Lars"-Hinweise).
        var isAckedByAnyone: Bool { status == "quittiert" || !ackedBy.isEmpty }

        /// Hat **diese** Person quittiert? Maßgeblich für den Quittieren-Knopf: sonst verschwindet er
        /// bei Elita, sobald Lars quittiert hat — beide sollen für sich bestätigen können.
        /// Ohne bekannte Person (Shared-Key) fällt es auf den geteilten Status zurück.
        func isAcked(by owner: String?) -> Bool {
            guard let o = owner, !o.isEmpty else { return isAckedByAnyone }
            return ackedBy.contains(o)
        }

        /// Zeitfenster für `Text(timerInterval:)` — endet spätestens beim Terminbeginn.
        var countdownRange: ClosedRange<Date> {
            let now = Date()
            let target = startAt
            return target > now ? now...target : target...target.addingTimeInterval(1)
        }
    }

    /// Statischer Teil — steht beim Start fest.
    var terminId: Int
    var category: String
}
