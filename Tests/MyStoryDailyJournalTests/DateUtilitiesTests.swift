import XCTest
@testable import MyStoryDailyJournal

final class DateUtilitiesTests: XCTestCase {
    func testStartOfDayNormalizesToMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!

        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 4
        components.hour = 23
        components.minute = 45
        let evening = calendar.date(from: components)!

        let start = DateUtilities.startOfDay(for: evening, calendar: calendar)
        let startComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)

        XCTAssertEqual(startComponents.hour, 0)
        XCTAssertEqual(startComponents.minute, 0)
        XCTAssertEqual(startComponents.day, 4)
    }

    func testDayIntervalSpansExactlyTwentyFourHours() {
        let calendar = Calendar(identifier: .gregorian)
        let interval = DateUtilities.dayInterval(containing: Date(), calendar: calendar)
        XCTAssertEqual(interval.duration, 24 * 60 * 60, accuracy: 1)
    }

    func testStartOfDayWithExplicitTimeZoneIgnoresDeviceTimeZone() {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 15
        components.hour = 2 // 2am UTC — still "yesterday" in Etc/GMT+8
        let instant = utcCalendar.date(from: components)!

        let startInFixedZone = DateUtilities.startOfDay(for: instant, timeZoneIdentifier: "Etc/GMT+8")
        var fixedCalendar = Calendar(identifier: .gregorian)
        fixedCalendar.timeZone = TimeZone(identifier: "Etc/GMT+8")!
        let day = fixedCalendar.component(.day, from: startInFixedZone)

        XCTAssertEqual(day, 14, "2am UTC on the 15th is still the 14th in a UTC-8 zone.")
    }
}
