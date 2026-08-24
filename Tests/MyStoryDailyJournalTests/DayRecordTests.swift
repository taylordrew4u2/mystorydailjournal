import XCTest
import SwiftData
@testable import MyStoryDailyJournal

final class DayRecordTests: XCTestCase {
    func testPreviewLineFallsBackToTagNamesWhenBodyTextIsEmpty() {
        let record = DayRecord(date: Date(), bodyText: "")
        record.tags = [Tag(name: "Good"), Tag(name: "Busy")]

        XCTAssertEqual(record.previewLine, "Good, Busy")
    }

    func testPreviewLinePrefersBodyTextOverTags() {
        let record = DayRecord(date: Date(), bodyText: "Went for a walk.\nSecond line.")
        record.tags = [Tag(name: "Good")]

        XCTAssertEqual(record.previewLine, "Went for a walk.")
    }

    func testPreviewLineIsEmptyWithNeitherTextNorTags() {
        let record = DayRecord(date: Date(), bodyText: "")
        XCTAssertEqual(record.previewLine, "")
    }
}
