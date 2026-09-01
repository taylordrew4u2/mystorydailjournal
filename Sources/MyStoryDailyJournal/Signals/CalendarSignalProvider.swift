import Foundation
import EventKit

/// Calendar events actually attended — declined/cancelled events are
/// filtered out (§4). The journal stores the event itself, not the guest
/// list; people enter a day only when the writer writes or tags them.
struct CalendarSignalProvider: DaySignalProvider {
    let kind: DaySignalKind = .calendar

    private let store = EKEventStore()

    func isAuthorized() async -> Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            return granted
        } catch {
            return false
        }
    }

    func collectSignals(for day: DateInterval) async throws -> [DaySignal] {
        guard await isAuthorized() else { return [] }

        let predicate = store.predicateForEvents(withStart: day.start, end: day.end, calendars: nil)
        let events = store.events(matching: predicate).filter { event in
            !event.isAllDay && event.status != .canceled && attendeeDeclined(event) == false
        }

        return events.map { event in
            let trimmedLocation = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
            let payload = CalendarPayload(
                eventIdentifier: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "Untitled event",
                location: (trimmedLocation?.isEmpty ?? true) ? nil : trimmedLocation
            )
            let signal = DaySignal(kind: .calendar, timestamp: event.startDate)
            signal.setPayload(payload)
            return signal
        }
    }

    /// True only if the organizer marked *this device's owner* as declined —
    /// a declined guest still shows up in `event.attendees`, so this can't
    /// just check attendee statuses in aggregate.
    private func attendeeDeclined(_ event: EKEvent) -> Bool {
        guard let attendees = event.attendees else { return false }
        return attendees.contains { $0.isCurrentUser && $0.participantStatus == .declined }
    }
}
