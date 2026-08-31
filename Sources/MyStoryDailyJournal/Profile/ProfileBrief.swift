import Foundation
import SwiftData

/// Picks the handful of learned facts that matter for *this* day and
/// renders them small enough for the on-device model to actually use.
///
/// A standing profile grows without limit; the model's attention does not.
/// Handing it everything known about a person makes the writing worse, not
/// better — so this retrieves against the day in hand (the people on it,
/// the places visited, the themes present) and spends a fixed character
/// budget on what's relevant, with voice always included because voice
/// shapes every sentence regardless of what happened.
enum ProfileBrief {
    /// Roughly three hundred tokens — enough to steer the voice and name
    /// what matters, small enough to leave the day itself the subject.
    static let defaultBudget = 1200

    /// What today is about, used to decide which stored facts are worth
    /// bringing.
    struct Cues: Equatable {
        var people: [String] = []
        var places: [String] = []
        var themes: [String] = []

        var isEmpty: Bool { people.isEmpty && places.isEmpty && themes.isEmpty }

        /// Everything the day says about itself: who's tagged on it, who
        /// its events list, where it went, and what its tags and photos
        /// were of.
        static func from(_ record: DayRecord) -> Cues {
            let signals = record.signals ?? []

            var people = (record.people ?? []).map(\.name)
            people += signals
                .filter { $0.kind == .calendar }
                .compactMap { $0.payload(as: CalendarPayload.self) }
                .flatMap(\.attendeeNames)

            let places = signals
                .filter { $0.kind == .visit }
                .compactMap { $0.payload(as: VisitPayload.self) }
                .filter { !$0.isPassingThrough }
                .map(\.placeName)

            var themes = (record.tags ?? []).map(\.name)
            themes += signals
                .filter { $0.kind == .photo }
                .compactMap { $0.payload(as: PhotoPayload.self) }
                .flatMap(\.sceneLabels)

            return Cues(people: people, places: places, themes: themes)
        }
    }

    /// The brief for one day, or nil when nothing has been learned yet.
    static func brief(
        for record: DayRecord?,
        in context: ModelContext,
        budget: Int = defaultBudget
    ) -> String? {
        let facts = (try? context.fetch(FetchDescriptor<ProfileFact>())) ?? []
        guard !facts.isEmpty else { return nil }
        let cues = record.map(Cues.from) ?? Cues()
        return render(select(from: facts, cues: cues, budget: budget))
    }

    /// Ranks and trims. Pure, so the choice of what the app tells the model
    /// about someone is testable rather than emergent.
    static func select(from facts: [ProfileFact], cues: Cues, budget: Int) -> [ProfileFact] {
        let candidates = facts.filter { !$0.isMuted }
        let scored = candidates
            .map { (fact: $0, score: score($0, cues: cues)) }
            .sorted { left, right in
                left.score == right.score
                    ? left.fact.subject.lowercased() < right.fact.subject.lowercased()
                    : left.score > right.score
            }

        var chosen: [ProfileFact] = []
        var spent = 0
        for candidate in scored where candidate.score > 0 {
            let cost = candidate.fact.sentence.count + 3
            guard spent + cost <= budget else { continue }
            chosen.append(candidate.fact)
            spent += cost
        }
        return chosen
    }

    /// Voice always counts. A person, place or theme the day itself raises
    /// counts for a lot. Everything else competes on how many days it rests
    /// on, so a long-standing pattern outranks last week's coincidence.
    private static func score(_ fact: ProfileFact, cues: Cues) -> Int {
        if fact.isPinned { return 10_000 }

        var score = min(fact.observationCount, 50)
        switch fact.kind {
        // A correction is the writer telling the app it got something
        // wrong. It outranks everything the app worked out for itself.
        case .correction:
            score += 5_000
        case .voice:
            score += 1_000
        case .person where matches(fact.subject, cues.people):
            score += 500
        case .place where matches(fact.subject, cues.places):
            score += 400
        case .theme where matches(fact.subject, cues.themes):
            score += 300
        case .rhythm:
            score += 100
        default:
            break
        }
        return score
    }

    private static func matches(_ subject: String, _ cues: [String]) -> Bool {
        cues.contains { $0.compare(subject, options: .caseInsensitive) == .orderedSame }
    }

    /// Grouped so the model reads it as a description of a person rather
    /// than a list of database rows.
    static func render(_ facts: [ProfileFact]) -> String? {
        guard !facts.isEmpty else { return nil }

        var lines: [String] = []
        for kind in ProfileFactKind.allCases {
            let sentences = facts.filter { $0.kind == kind }.map(\.sentence)
            guard !sentences.isEmpty else { continue }
            let heading = kind == .correction
                ? "Corrections the writer has made — follow these exactly"
                : kind.displayName
            lines.append("\(heading): \(sentences.joined(separator: " "))")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
