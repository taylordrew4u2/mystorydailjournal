import XCTest
import SwiftData
@testable import MyStoryDailyJournal

final class SharedItemIngestorTests: XCTestCase {
    private func makeContext() -> ModelContext {
        ModelContext(PersistenceController.makeContainer(inMemory: true))
    }

    func testIngestAttachesSignalWithoutTouchingBodyText() throws {
        let context = makeContext()
        let date = Date()

        SharedItemIngestor.ingest(title: "A note", text: "Shared from Notes.", sourceApp: "Notes", on: date, in: context)

        let record = DayRecordRepository.existingRecord(for: date, in: context)
        XCTAssertEqual(record?.bodyText, "", "Shared content must not overwrite the day's own text.")
        XCTAssertEqual(record?.signals?.count, 1)
        XCTAssertEqual(record?.signals?.first?.kind, .sharedItem)
    }

    func testIngestIgnoresBlankText() {
        let context = makeContext()
        let signal = SharedItemIngestor.ingest(title: nil, text: "   ", sourceApp: nil, in: context)
        XCTAssertNil(signal)
    }
}
