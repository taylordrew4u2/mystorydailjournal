import Foundation
import SwiftData

/// A freeform, user-entered name tagged onto a day. Deliberately lightweight:
/// no matching against the system Contacts database happens automatically
/// (see build spec §12) — a user can only link a real contact by explicitly
/// picking one via `CNContactPickerViewController` in a later milestone.
@Model
final class Person {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.distantPast
    var dayRecords: [DayRecord]? = []

    /// Who they are to the writer — "my sister", "a colleague" — answered
    /// by the writer themselves in the relationship prompts, never guessed.
    /// An entry that knows Dana is your sister reads like you wrote it; one
    /// that doesn't reads like a stranger describing your day.
    var relationship: String? = nil

    /// Anything else the writer wanted the app to know about them.
    var note: String? = nil

    /// How to refer to them, in the writer's words. Left alone unless they
    /// fill it in — a journal should never guess this.
    var pronouns: String? = nil

    /// When the writer was last asked about this person, so someone they
    /// skipped isn't put back at the front of the queue tomorrow.
    var askedAt: Date? = nil

    init(name: String, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
    }

    /// Whether the app still has an open question about them.
    var isDescribed: Bool {
        !(relationship ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// How this person reads in a profile brief.
    var descriptionForWriting: String? {
        var parts: [String] = []
        if let relationship, !relationship.isEmpty { parts.append(relationship) }
        if let pronouns, !pronouns.isEmpty { parts.append("goes by \(pronouns)") }
        if let note, !note.isEmpty { parts.append(note) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "; ")
    }
}
