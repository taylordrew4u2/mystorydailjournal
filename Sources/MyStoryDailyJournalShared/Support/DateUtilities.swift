import Foundation

enum DateUtilities {
    /// Start-of-day for `date` in the user's current calendar/timezone.
    /// `DayRecord.date` is always stored as this normalized value so a
    /// day can be looked up by its calendar date alone.
    static func startOfDay(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    static func dayInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let start = startOfDay(for: date, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    /// The full day containing `date`, bounded by midnight in a *specific*
    /// timezone — the day's own zone as stored on its `DayRecord`, not
    /// whichever one the device currently reports (§10).
    static func dayInterval(containing date: Date, timeZoneIdentifier: String) -> DateInterval {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return dayInterval(containing: date, calendar: calendar)
    }

    /// Start-of-day for `date` in a *specific* timezone rather than
    /// whichever one the device currently reports (§10: "a day is bounded
    /// by the user's local midnight at the time the day occurred"). Used
    /// to check whether a moment still falls within a day that started
    /// under a different timezone than the one currently in effect — the
    /// mechanism that keeps a day continuous across a timezone change.
    static func startOfDay(for date: Date, timeZoneIdentifier: String) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar.startOfDay(for: date)
    }
}
