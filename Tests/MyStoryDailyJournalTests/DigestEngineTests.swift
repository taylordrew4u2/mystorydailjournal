import XCTest
import SwiftData
@testable import MyStoryDailyJournal

final class DigestEngineTests: XCTestCase {
    private func makeContext() -> ModelContext {
        ModelContext(PersistenceController.makeContainer(inMemory: true))
    }

    /// Regression test: an earlier version of `generateDigestIfNeeded`
    /// deleted every non-visit signal on each run, which would have wiped
    /// out shared items and watched-folder files pushed in independently.
    func testRegenerationPreservesPushedSignalKinds() async throws {
        let context = makeContext()
        let date = Date()

        SharedItemIngestor.ingest(title: "A note", text: "From Notes.", sourceApp: "Notes", on: date, in: context)

        let record = DayRecordRepository.record(for: date, in: context)
        let fileSignal = DaySignal(kind: .fileWatch, timestamp: date)
        fileSignal.setPayload(FileWatchPayload(fileName: "a.txt", folderName: "Journal"))
        fileSignal.dayRecord = record
        context.insert(fileSignal)
        try context.save()

        _ = await DigestEngine.generateDigestIfNeeded(for: date, in: context)
        _ = await DigestEngine.generateDigestIfNeeded(for: date, in: context)

        let kinds = Set(record.signals?.map(\.kind) ?? [])
        XCTAssertTrue(kinds.contains(.sharedItem))
        XCTAssertTrue(kinds.contains(.fileWatch))
    }

    func testGenerateDigestNeverOverwritesUserWrittenDay() async {
        let context = makeContext()
        let date = Date()

        DayRecordRepository.appendQuickReply("My own words.", on: date, in: context)
        let record = await DigestEngine.generateDigestIfNeeded(for: date, in: context)

        XCTAssertEqual(record.bodyText, "My own words.")
        XCTAssertEqual(record.source, .userWritten)
    }

    func testGenerateDigestIsIdempotent() async {
        let context = makeContext()
        let date = Date()

        _ = await DigestEngine.generateDigestIfNeeded(for: date, in: context)
        _ = await DigestEngine.generateDigestIfNeeded(for: date, in: context)

        let descriptor = FetchDescriptor<DayRecord>()
        let allRecords = (try? context.fetch(descriptor)) ?? []
        XCTAssertEqual(allRecords.count, 1)
    }
}
