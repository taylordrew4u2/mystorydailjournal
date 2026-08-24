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

    /// Regression test for §10: a day that started under one timezone must
    /// stay the *same* record when the device's timezone changes mid-day
    /// (e.g. a flight lands and the phone updates its clock), rather than
    /// splitting into a second record purely because `TimeZone.current`
    /// changed. Simulates that by overriding `NSTimeZone.default` — the same
    /// thing the OS does when a device crosses zones — around a single
    /// record's lifetime.
    func testExistingRecordSurvivesDeviceTimeZoneChangeMidDay() {
        let originalTimeZone = NSTimeZone.default
        defer { NSTimeZone.default = originalTimeZone }

        NSTimeZone.default = TimeZone(identifier: "Etc/GMT+8")!
        let context = makeContext()

        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 15
        components.hour = 9
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Etc/GMT+8")!
        let dayStartInOldZone = calendar.date(from: components)!

        let record = DayRecordRepository.record(for: dayStartInOldZone, in: context)
        XCTAssertEqual(record.timeZoneIdentifier, "Etc/GMT+8")
        try? context.save()

        let tenHoursLater = dayStartInOldZone.addingTimeInterval(10 * 60 * 60)
        NSTimeZone.default = TimeZone(identifier: "Etc/GMT-9")!

        let found = DayRecordRepository.existingRecord(for: tenHoursLater, in: context)
        XCTAssertEqual(found?.date, record.date, "The same continuous day must be found, not missed, after a timezone change.")

        let descriptor = FetchDescriptor<DayRecord>()
        let allRecords = (try? context.fetch(descriptor)) ?? []
        XCTAssertEqual(allRecords.count, 1, "A timezone change mid-day must not create a duplicate day record.")
    }
}
