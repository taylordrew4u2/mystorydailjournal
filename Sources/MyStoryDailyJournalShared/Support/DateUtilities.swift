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
}
