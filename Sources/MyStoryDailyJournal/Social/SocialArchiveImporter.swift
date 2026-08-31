import Foundation
import SwiftData

/// Folds a social archive into the journal.
///
/// The single write path for archive content, the way `SharedItemIngestor`
/// is the single write path for pushed content — so "what does it mean to
/// import a network" has one answer no matter which network gets a reader
/// next.
enum SocialArchiveImporter {
    struct Summary: Equatable {
        /// Entries the archive offered.
        var read = 0
        /// Entries actually written; the rest were already here.
        var imported = 0
        /// Days that had no record until this import made one.
        var daysCreated = 0

        var skipped: Int { read - imported }
        var isEmpty: Bool { read == 0 }
    }

    /// Writes every entry not already present, on the day it happened.
    ///
    /// Idempotent by `externalID`: importing the same export twice, or a
    /// fresh export that overlaps the last one, adds each post once. That
    /// matters more here than elsewhere — an archive is something a person
    /// re-downloads every few months, and the obvious thing to do with the
    /// new one is import it on top of the old.
    ///
    /// Existing text is never touched. An imported post is evidence about a
    /// day, exactly like a visit or a photo; it is not the day's entry, and
    /// a day the writer has already written stays as they wrote it.
    @discardableResult
    static func ingest(
        _ entries: [SocialArchiveEntry],
        in context: ModelContext
    ) -> Summary {
        var summary = Summary(read: entries.count)
        guard !entries.isEmpty else { return summary }

        var known = existingExternalIDs(in: context)

        for entry in entries {
            guard !known.contains(entry.externalID) else { continue }
            known.insert(entry.externalID)

            let hadRecord = DayRecordRepository.existingRecord(for: entry.timestamp, in: context) != nil
            let record = DayRecordRepository.record(for: entry.timestamp, in: context)
            if !hadRecord { summary.daysCreated += 1 }

            let signal = DaySignal(kind: .socialPost, timestamp: entry.timestamp)
            signal.setPayload(SocialPostPayload(
                network: entry.network,
                form: entry.form,
                text: entry.text,
                placeName: entry.placeName,
                latitude: entry.latitude,
                longitude: entry.longitude,
                mediaCount: entry.mediaCount,
                externalID: entry.externalID
            ))
            signal.dayRecord = record
            context.insert(signal)
            summary.imported += 1
        }

        // One save for the whole archive. A person's export can be thousands
        // of posts across years; saving per post turns an import into a
        // minutes-long stall.
        try? context.save()
        return summary
    }

    /// Every archive ID already in the store. Fetched once and held as a
    /// set, because the alternative — a predicate per entry — is one query
    /// per post across the writer's entire history.
    private static func existingExternalIDs(in context: ModelContext) -> Set<String> {
        let kind = DaySignalKind.socialPost.rawValue
        let descriptor = FetchDescriptor<DaySignal>(
            predicate: #Predicate { $0.kindRaw == kind }
        )
        let signals = (try? context.fetch(descriptor)) ?? []

        var ids: Set<String> = []
        for signal in signals {
            if let payload = signal.payload(as: SocialPostPayload.self) {
                ids.insert(payload.externalID)
            }
        }
        return ids
    }

    /// Removes everything imported from a given network, for the writer who
    /// changes their mind. Days the import created are left alone: by the
    /// time they're asked for, the digest may have written them, and this is
    /// meant to undo an import, not erase a stretch of the journal.
    @discardableResult
    static func forget(network: String, in context: ModelContext) -> Int {
        let kind = DaySignalKind.socialPost.rawValue
        let descriptor = FetchDescriptor<DaySignal>(
            predicate: #Predicate { $0.kindRaw == kind }
        )
        let signals = (try? context.fetch(descriptor)) ?? []

        var removed = 0
        for signal in signals {
            guard let payload = signal.payload(as: SocialPostPayload.self),
                  payload.network == network else { continue }
            context.delete(signal)
            removed += 1
        }
        try? context.save()
        return removed
    }
}
