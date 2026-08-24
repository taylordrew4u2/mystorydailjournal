import Foundation
import SwiftData

/// The single write path for content pushed in from outside the app —
/// used by both the Share Extension (M7) and the Shortcuts ingestion
/// `AppIntent` (M8), so "what does it mean to receive shared content"
/// only has one answer (§4, §10).
enum SharedItemIngestor {
    @discardableResult
    static func ingest(
        title: String?,
        text: String,
        sourceApp: String?,
        on date: Date = .now,
        in context: ModelContext
    ) -> DaySignal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let record = DayRecordRepository.record(for: date, in: context)
        let payload = SharedItemPayload(title: title, text: trimmed, sourceApp: sourceApp)

        let signal = DaySignal(kind: .sharedItem, timestamp: .now)
        signal.setPayload(payload)
        signal.dayRecord = record
        context.insert(signal)
        try? context.save()
        return signal
    }
}
