import Foundation

/// What leaves the phone when the writer shares a day, worked out before
/// anything is handed to the share sheet.
///
/// A journal is written on the assumption that nobody else reads it, and
/// this app has spent three milestones making entries *more* identifying —
/// real venue names, the people who were there, where the photos were
/// taken. Sharing one has to be the moment all of that is visible and
/// removable, so the share copy is assembled here, shown in full before it
/// goes anywhere, and redacted per-term at the writer's choice. The stored
/// entry is never touched by any of it.
enum ShareableEntry {
    /// A name in the entry that identifies a person or a place, with the
    /// neutral wording it can be swapped for.
    struct SensitiveTerm: Identifiable, Equatable, Sendable {
        enum Kind: String, Sendable {
            case person
            case place
        }

        var term: String
        var kind: Kind
        /// What the shared copy says instead — "a friend", "the café".
        var replacement: String

        var id: String { "\(kind.rawValue)|\(term.lowercased())" }
    }

    /// Everything in this entry that names someone or somewhere, and
    /// actually appears in the text. Drawn from the day's own record — the
    /// people the writer tagged and the places they confirmed — so the list
    /// is exactly as good as what the app already knows, and never a guess
    /// at names it has never seen.
    static func sensitiveTerms(in record: DayRecord, text: String) -> [SensitiveTerm] {
        var terms: [SensitiveTerm] = []

        for person in record.people ?? [] {
            terms.append(SensitiveTerm(term: person.name, kind: .person, replacement: "a friend"))
        }

        for signal in record.signals ?? [] where signal.kind == .visit {
            guard let payload = signal.payload(as: VisitPayload.self) else { continue }
            let replacement = placeReplacement(for: payload)
            terms.append(SensitiveTerm(term: payload.placeName, kind: .place, replacement: replacement))
            if let raw = payload.rawPlaceName {
                terms.append(SensitiveTerm(term: raw, kind: .place, replacement: replacement))
            }
        }

        for signal in record.signals ?? [] where signal.kind == .calendar {
            guard let location = signal.payload(as: CalendarPayload.self)?.location else { continue }
            terms.append(SensitiveTerm(term: location, kind: .place, replacement: "somewhere"))
        }

        // Only what's really in the words, deduplicated, longest first so
        // the chips read from most specific to least.
        var seen = Set<String>()
        return terms
            .filter { term in
                let trimmed = term.term.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count > 2, text.range(of: trimmed, options: .caseInsensitive) != nil else { return false }
                return seen.insert(term.id).inserted
            }
            .sorted { $0.term.count > $1.term.count }
    }

    /// What a place becomes when its name is taken out: what the writer
    /// said it was, or what Maps called it, and otherwise nothing specific
    /// at all.
    private static func placeReplacement(for payload: VisitPayload) -> String {
        if let category = payload.categoryLabel, !category.isEmpty {
            return "the \(category)"
        }
        if let kind = payload.placeKindRaw.flatMap(PlaceKind.init(rawValue:)), !kind.isPassingThrough {
            return kind.entryPhrase
        }
        return "somewhere"
    }

    /// The copy that will be shared: the entry, optionally under its date,
    /// with every chosen name swapped out.
    static func text(
        body: String,
        date: Date? = nil,
        redacting terms: [SensitiveTerm] = [],
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) -> String {
        var replacements: [String: String] = [:]
        for term in terms {
            replacements[term.term] = term.replacement
        }
        let redacted = PlaceNameResolver.rename(body, replacements: replacements)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let date else { return redacted }

        var style = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day().year()
        style.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let headline = date.formatted(style)
        return redacted.isEmpty ? headline : "\(headline)\n\n\(redacted)"
    }
}
