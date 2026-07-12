import UserNotifications

/// Plant lokale Erinnerungen (funktionieren offline) aus dem Dashboard:
/// anstehende Termine (Vortag 18:00) + bald ablaufende Lebensmittel (Vortag 09:00).
/// Idempotent: eigene Requests (Präfix) werden vor dem Neuplanen entfernt.
enum LocalReminders {
    private static let prefix = "fp-local-"

    static func reschedule(termine: [TerminShort], vorrat: [VorratShort], abfuhr: [AbfuhrNext] = []) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { pending in
            let center = UNUserNotificationCenter.current()
            let old = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)

            var requests: [UNNotificationRequest] = []
            for t in termine.prefix(30) {
                guard let day = DateText.parse(date: t.date) else { continue }
                let base = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
                let fire = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: base) ?? base
                if let r = make(id: prefix + "termin-\(t.id)",
                                title: "📅 Termin morgen: \(t.title)",
                                body: DateText.pretty(t.date) + (t.time.map { " · \($0)" } ?? ""),
                                fire: fire) { requests.append(r) }
            }
            for v in vorrat.prefix(30) {
                guard let mhd = v.mhd, let day = DateText.parse(date: mhd) else { continue }
                let base = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
                let fire = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: base) ?? base
                if let r = make(id: prefix + "mhd-\(v.id)",
                                title: "🍽️ MHD bald: \(v.name)",
                                body: "Läuft am \(DateText.pretty(mhd)) ab.",
                                fire: fire) { requests.append(r) }
            }
            for a in abfuhr {
                guard let dt = a.datum, let day = DateText.parse(date: dt) else { continue }
                let base = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
                let fire = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: base) ?? base
                if let r = make(id: prefix + "abfuhr-\(a.kategorie)-\(dt)",
                                title: "🗑️ Abfuhr morgen: \(a.label)",
                                body: "Tonne heute Abend rausstellen (\(DateText.pretty(dt))).",
                                fire: fire) { requests.append(r) }
            }
            for r in requests { center.add(r) }
        }
    }

    private static func make(id: String, title: String, body: String, fire: Date) -> UNNotificationRequest? {
        guard fire > Date() else { return nil } // nur Zukunft terminieren
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}
