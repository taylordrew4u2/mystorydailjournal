import Foundation

/// Turns what a reverse geocoder produced ("480 Larkin Street") into what
/// the writer actually calls the place ("Blue Bottle"), using the answer
/// they gave to the guided question about it.
///
/// Pure string work, deliberately: the diary shouldn't read like a
/// delivery route, and the only thing that knows what's at an address is
/// the person who was standing there.
enum PlaceNameResolver {
    /// Whether a place name is really just coordinates dressed up — a
    /// street address, a plus code, or the geocoder's "Unknown place"
    /// fallback. These are the names worth asking about; a venue name that
    /// came back clean ("Golden Gate Park") is left alone.
    static func looksLikeAddress(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.compare("Unknown place", options: .caseInsensitive) == .orderedSame { return true }
        // A house number is the giveaway. Venue names with digits in them
        // ("Bar 33") are rare enough that asking about them anyway costs
        // one question and gains a confirmation.
        return trimmed.contains(where: \.isNumber)
    }

    /// The venue name hiding inside a free-text answer. "That's Blue Bottle,
    /// we got breakfast" and "we were at Blue Bottle" both yield
    /// "Blue Bottle"; a shrug ("no idea") yields nil, and so does anything
    /// long enough to be a story rather than a name — in both cases the
    /// original place name stays as it is.
    static func venueName(fromAnswer answer: String) -> String? {
        var text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // The name is whatever comes before the first clause break: people
        // answer "Blue Bottle, met Dana there" far more often than they
        // answer with a bare noun phrase.
        if let breakRange = text.rangeOfCharacter(from: clauseBreaks) {
            text = String(text[text.startIndex..<breakRange.lowerBound])
        }
        for joiner in clauseJoiners {
            if let range = text.range(of: joiner, options: [.caseInsensitive]) {
                text = String(text[text.startIndex..<range.lowerBound])
            }
        }

        // "We got breakfast at Blue Bottle" — the name follows the "at".
        if let atRange = text.range(of: " at ", options: [.caseInsensitive, .backwards]) {
            let candidate = text[atRange.upperBound...].trimmingCharacters(in: .whitespaces)
            if !candidate.isEmpty, candidate.split(separator: " ").count <= maximumWordCount {
                text = candidate
            }
        }

        text = strippingLeadingFillers(from: text)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”"))

        guard !text.isEmpty, !isNonAnswer(text) else { return nil }
        let words = text.split(separator: " ")
        guard !words.isEmpty, words.count <= maximumWordCount, text.count <= 60 else { return nil }
        // Anything starting with a number is the address coming back at us
        // ("480", "480 Larkin"), not the name of what's there.
        guard let first = text.first, !first.isNumber, text.contains(where: \.isLetter) else { return nil }

        return text
    }

    /// Swaps every confirmed address for its venue name wherever it appears
    /// in a piece of text. Longest keys first, so a street that contains
    /// another street's name can't be half-replaced.
    static func rename(_ text: String, replacements: [String: String]) -> String {
        var result = text
        for (raw, name) in replacements.sorted(by: { $0.key.count > $1.key.count }) {
            let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedRaw.isEmpty, trimmedRaw.compare(name, options: .caseInsensitive) != .orderedSame else {
                continue
            }
            result = result.replacingOccurrences(of: trimmedRaw, with: name, options: [.caseInsensitive])
        }
        return result
    }

    private static let maximumWordCount = 6

    private static let clauseBreaks = CharacterSet(charactersIn: ".,;:!?\n—–")

    private static let clauseJoiners = [" where ", " which ", " and we ", " and i ", " because ", " so we ", " with "]

    private static let leadingFillers = [
        "that's", "thats", "that is", "that was", "it's", "its", "it is", "it was",
        "this is", "this was", "the place is", "we were at", "i was at", "we went to",
        "i went to", "we were", "i was", "just", "the", "a", "an", "my", "our",
    ]

    private static let nonAnswers: Set<String> = [
        "idk", "i dont know", "i don't know", "dunno", "no idea", "not sure",
        "nothing", "none", "n/a", "na", "unsure", "cant remember", "can't remember",
        "dont remember", "don't remember", "?",
    ]

    private static func strippingLeadingFillers(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespaces)
        var didStrip = true
        while didStrip {
            didStrip = false
            for filler in leadingFillers {
                let prefix = filler + " "
                if result.lowercased().hasPrefix(prefix) {
                    result = String(result.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                    didStrip = true
                    break
                }
            }
        }
        return result
    }

    private static func isNonAnswer(_ text: String) -> Bool {
        nonAnswers.contains(text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".?! ")))
    }
}
