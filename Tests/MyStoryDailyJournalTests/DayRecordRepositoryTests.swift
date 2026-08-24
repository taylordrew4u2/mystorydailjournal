import XCTest
import SwiftData
@testable import MyStoryDailyJournal

final class DayRecordRepositoryTests: XCTestCase {
    private func makeContext() -> ModelContext {
        let container = PersistenceController.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    func testRecordForDateIsIdempotent() {
        let context = makeContext()
        let date = Date()

        let first = DayRecordRepository.record(for: date, in: context)
        let second = DayRecordRepository.record(for: date, in: context)

        XCTAssertEqual(first.date, second.date)

        let descriptor = FetchDescriptor<DayRecord>()
        let allRecords = (try? context.fetch(descriptor)) ?? []
        XCTAssertEqual(allRecords.count, 1, "Looking up the same day twice must not create a duplicate.")
    }

    func testAppendQuickReplyCreatesRecordWithUserWrittenSource() {
        let context = makeContext()
        DayRecordRepository.appendQuickReply("Went for a run.", on: Date(), in: context)

        let descriptor = FetchDescriptor<DayRecord>()
        let record = try? context.fetch(descriptor).first
        XCTAssertEqual(record?.bodyText, "Went for a run.")
        XCTAssertEqual(record?.source, .userWritten)
    }

    func testAppendQuickReplyAppendsRatherThanOverwrites() {
        let context = makeContext()
        let date = Date()
        DayRecordRepository.appendQuickReply("First line.", on: date, in: context)
        DayRecordRepository.appendQuickReply("Second line.", on: date, in: context)

        let descriptor = FetchDescriptor<DayRecord>()
        let records = (try? context.fetch(descriptor)) ?? []
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.bodyText, "First line.\nSecond line.")
    }

    func testAppendQuickReplyIgnoresBlankText() {
        let context = makeContext()
        DayRecordRepository.appendQuickReply("   \n  ", on: Date(), in: context)

        let descriptor = FetchDescriptor<DayRecord>()
        let records = (try? context.fetch(descriptor)) ?? []
        XCTAssertTrue(records.isEmpty)
    }
}
