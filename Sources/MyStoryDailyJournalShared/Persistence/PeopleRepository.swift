import Foundation
import SwiftData

/// One-tap person tagging (§3, §5 metadata strip). `Person` stays
/// deliberately freeform — no Contacts matching happens here (§12).
enum PeopleRepository {
    /// People tagged on the most recent few days, most recent first, for
    /// a one-tap "recent people" list rather than making the user retype
    /// a name every time.
    static func recentPeople(in context: ModelContext, limit: Int = 8) -> [Person] {
        var descriptor = FetchDescriptor<DayRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 60
        let recentDays = (try? context.fetch(descriptor)) ?? []

        var seen = Set<UUID>()
        var ordered: [Person] = []
        for day in recentDays {
            for person in day.people ?? [] where !seen.contains(person.id) {
                seen.insert(person.id)
                ordered.append(person)
                if ordered.count >= limit { return ordered }
            }
        }
        return ordered
    }

    /// Finds an existing `Person` by name (case-insensitive) or creates
    /// one — names are how this app recognizes "the same person," since
    /// there's no Contacts link.
    static func findOrCreatePerson(named name: String, in context: ModelContext) -> Person {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var descriptor = FetchDescriptor<Person>()
        descriptor.fetchLimit = 200
        if let existing = (try? context.fetch(descriptor))?.first(where: {
            $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) {
            return existing
        }
        let person = Person(name: trimmed)
        context.insert(person)
        return person
    }

    static func toggle(_ person: Person, on record: DayRecord, in context: ModelContext) {
        if record.people == nil { record.people = [] }
        if let index = record.people?.firstIndex(where: { $0.id == person.id }) {
            record.people?.remove(at: index)
        } else {
            record.people?.append(person)
        }
        try? context.save()
    }
}
