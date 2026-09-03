import Foundation
import SwiftData

/// Decides who the app should ask about next.
///
/// The journal knows a name appears on forty days; it has no idea whether
/// that's a sister, a manager or a dog walker, and it must never guess.
/// So it asks — starting with whoever turns up most, because getting the
/// most-present person right improves the most entries.
enum RelationshipPrompter {
    /// How long to leave someone alone after the writer skips them. Long
    /// enough not to nag, short enough that a change of mind is easy.
    static let skipInterval: TimeInterval = 14 * 24 * 60 * 60

    /// People worth asking about, most-present first: already saved by the
    /// writer, not yet described, and not skipped recently.
    static func peopleToAskAbout(
        in context: ModelContext,
        now: Date = .now,
        limit: Int = 10
    ) -> [Person] {
        let everyone = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        return everyone
            .filter { person in
                guard !person.isDescribed else { return false }
                guard !(person.dayRecords ?? []).isEmpty else { return false }
                if let askedAt = person.askedAt, now.timeIntervalSince(askedAt) < skipInterval {
                    return false
                }
                return true
            }
            .sorted { left, right in
                let leftDays = (left.dayRecords ?? []).count
                let rightDays = (right.dayRecords ?? []).count
                return leftDays == rightDays
                    ? left.name.lowercased() < right.name.lowercased()
                    : leftDays > rightDays
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Whether the pen should show that it has something to ask.
    static func hasQuestions(in context: ModelContext, now: Date = .now) -> Bool {
        !peopleToAskAbout(in: context, now: now, limit: 1).isEmpty
    }

    /// The answers, recorded on the person themselves so every future entry
    /// that mentions them can be written knowing who they are.
    static func describe(
        _ person: Person,
        relationship: String?,
        pronouns: String? = nil,
        note: String? = nil,
        now: Date = .now,
        in context: ModelContext
    ) {
        person.relationship = trimmed(relationship)
        person.pronouns = trimmed(pronouns)
        person.note = trimmed(note)
        person.askedAt = now
        try? context.save()
    }

    /// Skipping is an answer too: it means "don't ask me about this one
    /// right now", not "never".
    static func skip(_ person: Person, now: Date = .now, in context: ModelContext) {
        person.askedAt = now
        try? context.save()
    }

    private static func trimmed(_ value: String?) -> String? {
        let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty ? nil : cleaned
    }

    /// The everyday answers, offered as one tap each. "Someone else" is
    /// there because these will never cover everyone who matters.
    static let commonRelationships = [
        "My partner", "My wife", "My husband",
        "My mum", "My dad", "My sister", "My brother", "My child",
        "A close friend", "A friend", "A colleague", "My boss",
        "My neighbour", "My roommate",
    ]
}
