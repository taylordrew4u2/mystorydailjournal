import Foundation
import SwiftData

/// What the writer says the app got wrong, kept as a standing instruction.
///
/// Regenerating a bad entry fixes one day. Saying *why* it was bad fixes
/// every day after it — "you keep calling my flat 'the residence'", "don't
/// say I was productive", "Alex is my brother, not a coworker". These are
/// stored as `ProfileFact`s of kind `.correction`, which `ProfileBrief`
/// always sends to the model ahead of anything the app worked out for
/// itself, and which the writer can read and delete like everything else.
enum EntryCorrection {
    /// Long enough to be a real instruction, short enough that the model
    /// isn't handed an essay per entry.
    static let maximumLength = 240

    /// Records a correction, or returns nil for an empty one. Saying the
    /// same thing twice sharpens the existing correction rather than
    /// stacking a duplicate.
    @discardableResult
    static func record(_ text: String, on date: Date? = nil, in context: ModelContext) -> ProfileFact? {
        let cleaned = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumLength))
        guard !cleaned.isEmpty else { return nil }

        let key = subject(for: cleaned)
        let existing = (try? context.fetch(FetchDescriptor<ProfileFact>()))?
            .first { $0.kind == .correction && $0.subject == key }

        if let existing {
            existing.detail = cleaned
            existing.observationCount += 1
            existing.lastObserved = date ?? .now
            existing.isMuted = false
            try? context.save()
            return existing
        }

        let fact = ProfileFact(
            kind: .correction,
            subject: key,
            detail: cleaned,
            observationCount: 1,
            firstObserved: date ?? .now,
            lastObserved: date ?? .now
        )
        context.insert(fact)
        try? context.save()
        return fact
    }

    /// Identity for a correction: its own words, normalized, so re-saying
    /// it is recognized as the same instruction.
    static func subject(for text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func all(in context: ModelContext) -> [ProfileFact] {
        let facts = (try? context.fetch(FetchDescriptor<ProfileFact>())) ?? []
        return facts
            .filter { $0.kind == .correction && !$0.isMuted }
            .sorted { $0.lastObserved > $1.lastObserved }
    }
}
