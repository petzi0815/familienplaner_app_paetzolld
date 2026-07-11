import EventKit

/// EventKit-Schreibzugriff (write-only, iOS 17+): Termine/Ereignisse in den iOS-Kalender eintragen.
enum CalendarSync {
    enum CalError: Error, Equatable { case denied }

    static func addEvent(title: String, date: Date, allDay: Bool, notes: String?) async -> Result<Void, Error> {
        let store = EKEventStore()
        do {
            let granted = try await store.requestWriteOnlyAccessToEvents()
            guard granted else { return .failure(CalError.denied) }
            let event = EKEvent(eventStore: store)
            event.title = title
            event.startDate = date
            event.endDate = allDay ? date : date.addingTimeInterval(3600)
            event.isAllDay = allDay
            event.notes = notes
            event.calendar = store.defaultCalendarForNewEvents
            try store.save(event, span: .thisEvent, commit: true)
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
