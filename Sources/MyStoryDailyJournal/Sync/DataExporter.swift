import Foundation
import SwiftData

/// Export to Markdown/JSON, and full local delete that also has to purge
/// the CloudKit private database, not just the local store (§12).
enum DataExporter {
    enum Format: String, CaseIterable, Identifiable {
        case markdown = "Markdown"
        case json = "JSON"

        var id: String { rawValue }
        var fileExtension: String { self == .markdown ? "md" : "json" }
    }

    /// Writes every `DayRecord` to a temp file and returns its URL, ready
    /// to hand to `ShareLink`/`UIActivityViewController`.
    static func export(format: Format, from context: ModelContext) throws -> URL {
        let descriptor = FetchDescriptor<DayRecord>(sortBy: [SortDescriptor(\.date, order: .forward)])
        let records = try context.fetch(descriptor)

        let data: Data = switch format {
        case .markdown: Data(markdown(for: records).utf8)
        case .json: try json(for: records)
        }

        let url = FileManager.default.temporaryDirectory
            .appending(path: "MyStoryExport-\(Int(Date().timeIntervalSince1970)).\(format.fileExtension)")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func markdown(for records: [DayRecord]) -> String {
        records.map { record in
            let heading = record.date.formatted(.dateTime.year().month(.wide).day())
            let sourceNote = record.isUserWritten ? "" : " (auto-generated)"
            return "## \(heading)\(sourceNote)\n\n\(record.bodyText)\n"
        }.joined(separator: "\n")
    }

    private struct ExportedDay: Codable {
        let date: Date
        let source: String
        let bodyText: String
        let tags: [String]
        let people: [String]
    }

    private static func json(for records: [DayRecord]) throws -> Data {
        let exported = records.map { record in
            ExportedDay(
                date: record.date,
                source: record.source.rawValue,
                bodyText: record.bodyText,
                tags: (record.tags ?? []).map(\.name),
                people: (record.people ?? []).map(\.name)
            )
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(exported)
    }

    /// Deletes every record from the local store. Because the container is
    /// CloudKit-backed (§11), this deletion syncs as a tombstone to the
    /// user's private database the same way any other local change does —
    /// there's no separate CloudKit purge call to make. That sync isn't
    /// instantaneous or independently confirmable from here, which is a
    /// real limitation worth surfacing to the user rather than promising
    /// an immediate guarantee.
    static func deleteAllData(in context: ModelContext) throws {
        try context.delete(model: DaySignal.self)
        try context.delete(model: DayRecord.self)
        try context.delete(model: Person.self)
        try context.delete(model: Tag.self)
        try context.save()
    }
}
