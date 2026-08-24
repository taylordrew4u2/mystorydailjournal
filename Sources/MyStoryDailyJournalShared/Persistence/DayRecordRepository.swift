import Foundation
import SwiftData

/// Idempotent lookups/writes against `DayRecord`. Both the notification
/// quick-reply handler (which may run without any UI on screen) and the
/// entry views go through here, so "find or create today's record" always
/// behaves the same way.
enum DayRecordRepository {
    @discardableResult
    static func record(for date: Date, in context: ModelContext) -> DayRecord {
        let day = DateUtilities.startOfDay(for: date)
        var descriptor = FetchDescriptor<DayRecord>(
            predicate: #Predicate { $0.date == day }
        )
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let record = DayRecord(date: day, source: .userWritten, bodyText: "")
        context.insert(record)
        return record
    }

    /// Appends quick-reply text from a notification action to the day it
    /// arrived on, creating the day's record if needed. Never overwrites
    /// existing text — a second quick reply the same day appends a new line.
    static func appendQuickReply(_ text: String, on date: Date, in context: ModelContext) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let record = record(for: date, in: context)
        if record.bodyText.isEmpty {
            record.bodyText = trimmed
        } else {
            record.bodyText += "\n" + trimmed
        }
        record.source = .userWritten
        record.editedAt = .now
        try? context.save()
    }
}
