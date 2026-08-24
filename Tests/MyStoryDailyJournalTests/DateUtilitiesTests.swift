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
}
