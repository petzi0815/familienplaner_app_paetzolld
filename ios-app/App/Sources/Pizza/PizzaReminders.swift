import UserNotifications

/// Lokale Erinnerungen fuer die Handgriffe eines Pizza-Plans (funktionieren offline).
///
/// BEGRUENDUNG eigene Datei statt Erweiterung von `LocalReminders`: die beiden haben
/// unvereinbare Lebenszyklen. `LocalReminders.reschedule` ist ein VOLLABGLEICH — es loescht alles
/// mit Praefix `fp-local-` und setzt es aus dem Dashboard neu; es laeuft bei jedem Dashboard-Refresh.
/// Ein Pizza-Plan wird dagegen EINMAL bewusst vom Nutzer gestellt und darf von einem
/// Dashboard-Refresh nicht weggeraeumt werden (und umgekehrt duerfen Pizza-Schritte den
/// Vorrats-/Abfuhr-Abgleich nicht stoeren). Getrennter Praefix `fp-pizza-` + eigene Datei halten
/// die zwei Idempotenz-Bereiche sauber auseinander; die Signatur von `LocalReminders.reschedule`
/// bleibt unangetastet. Nebenbei bleibt so das ganze Pizza-Modul in einem Ordner.
///
/// Idempotent: eigene Requests (Praefix) werden vor dem Neuplanen entfernt.
enum PizzaReminders {
    static let prefix = "fp-pizza-"

    /// Stellt Erinnerungen fuer alle AKTIONS-Schritte des Plans (Gaerbloecke laufen von allein).
    /// Rueckgabe = Anzahl tatsaechlich gestellter Erinnerungen; 0 heisst: keine Erlaubnis oder
    /// alle Schritte liegen in der Vergangenheit.
    @discardableResult
    static func plane(plan: PizzaPlan, calendar: Calendar = .current) async -> Int {
        let center = UNUserNotificationCenter.current()
        // Fragt nur beim ersten Mal — eine bereits erteilte/verweigerte Entscheidung wird
        // ohne erneuten Dialog zurueckgegeben.
        let erlaubt = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard erlaubt else { return 0 }

        await loesche()

        let essen = PizzaCalculator.uhrzeit(plan.essenszeit, calendar: calendar)
        var gestellt = 0
        for s in plan.schritte where s.istAktion {
            guard s.zeit > Date() else { continue }   // nur Zukunft terminieren
            let content = UNMutableNotificationContent()
            content.title = "🍕 " + s.titel
            content.subtitle = "Essen um \(essen) Uhr"
            content.body = s.detail ?? "Es ist so weit."
            content.sound = .default

            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: s.zeit)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: prefix + s.id, content: content, trigger: trigger)
            do { try await center.add(req); gestellt += 1 } catch { continue }
        }
        return gestellt
    }

    /// Entfernt alle noch ausstehenden Pizza-Erinnerungen (fremde Requests bleiben unberuehrt).
    static func loesche() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Anzahl aktuell gestellter Pizza-Erinnerungen (fuer die Anzeige im Planer).
    static func anzahlGestellt() async -> Int {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(prefix) }.count
    }
}
