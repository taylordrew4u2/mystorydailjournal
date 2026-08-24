import Foundation
import SwiftData

/// Idempotent lookups/writes against `DayRecord`. Both the notification
/// quick-reply handler (which may run without any UI on screen) and the
/// entry views go through here, so "find or create today's record" always
/// behaves the same way.
enum DayRecordRepository {
    /// Read-only lookup — never inserts. For callers that just want to
    /// know whether a day already has a record (e.g. refreshing the Live
    /// Activity's "journaled" flag) without side-effecting one into
    /// existence just by asking.
    ///
    /// Two passes: first an exact match on the device's *current*-timezone
    /// day boundary (the common case), then — only if that misses — a
    /// short look-back at the most recent record to see whether `date`
    /// still falls inside *that* record's own day, computed with *its*
    /// stored `timeZoneIdentifier` rather than the current one (§10). That
    /// second pass is what keeps one continuous day from splitting into two
    /// records when the device's timezone changes mid-day while traveling —
    /// without it, "now" could resolve to a brand-new calendar day purely
    /// because the clock's zone just changed, not because a new day
    /// actually started.
    static func existingRecord(for date: Date, in context: ModelContext) -> DayRecord? {
        let day = DateUtilities.startOfDay(for: date)
        var exactDescriptor = FetchDescriptor<DayRecord>(
            predicate: #Predicate { $0.date == day }
        )
        exactDescriptor.fetchLimit = 1
        if let exact = try? context.fetch(exactDescriptor).first {
            return exact
        }

        guard let searchStart = Calendar.current.date(byAdding: .day, value: -1, to: day) else {
            return nil
        }
        var nearbyDescriptor = FetchDescriptor<DayRecord>(
            predicate: #Predicate { $0.date >= searchStart && $0.date <= day },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        nearbyDescriptor.fetchLimit = 5
        let nearby = (try? context.fetch(nearbyDescriptor)) ?? []

        return nearby.first { record in
            let ownDayStart = DateUtilities.startOfDay(for: record.date, timeZoneIdentifier: record.timeZoneIdentifier)
            guard let ownDayEnd = Calendar.current.date(byAdding: .day, value: 1, to: ownDayStart) else {
                return false
            }
            return date >= ownDayStart && date < ownDayEnd
        }
    }

    /// Finds the day's record, or creates one in the `.blank` state — not
    /// `.userWritten`. Defaulting to `.userWritten` here was a real bug:
    /// `DigestEngine` skips any day whose source already counts as
    /// user-written, so a record born `.userWritten` before anyone actually
    /// wrote anything could never become a digest — it would sit forever
    /// as an empty "written" day. `.blank` leaves the door open until an
    /// actual write happens (see `DayRecordSource.blank`'s doc comment).
    @discardableResult
    static func record(for date: Date, in context: ModelContext) -> DayRecord {
        if let existing = existingRecord(for: date, in: context) {
            return existing
        }

        let record = DayRecord(date: DateUtilities.startOfDay(for: date), source: .blank, bodyText: "")
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
