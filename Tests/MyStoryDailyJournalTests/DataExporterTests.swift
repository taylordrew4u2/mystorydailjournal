import XCTest
import SwiftData
@testable import MyStoryDailyJournal

final class DataExporterTests: XCTestCase {
    private func makeContext() -> ModelContext {
        ModelContext(PersistenceController.makeContainer(inMemory: true))
    }

    func testExportMarkdownIncludesBodyText() throws {
        let context = makeContext()
        let record = DayRecordRepository.record(for: Date(), in: context)
        record.bodyText = "Went for a long walk."
        try context.save()

        let url = try DataExporter.export(format: .markdown, from: context)
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("Went for a long walk."))
    }

    func testExportJSONRoundTripsRecordCount() throws {
        let context = makeContext()
        DayRecordRepository.appendQuickReply("Day one.", on: Date(), in: context)
        DayRecordRepository.appendQuickReply(
            "Day two.",
            on: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            in: context
        )

        let url = try DataExporter.export(format: .json, from: context)
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertEqual(decoded?.count, 2)
    }

    func testDeleteAllDataRemovesEveryRecord() throws {
        let context = makeContext()
        DayRecordRepository.appendQuickReply("Something.", on: Date(), in: context)

        try DataExporter.deleteAllData(in: context)

        let remaining = try context.fetch(FetchDescriptor<DayRecord>())
        XCTAssertTrue(remaining.isEmpty)
    }
}
