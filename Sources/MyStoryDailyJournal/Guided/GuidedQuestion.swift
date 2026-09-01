import Foundation

/// One prompt in the guided flow, plus everything the day already knows
/// about what it's asking: the photos to show alongside it, any names the
/// writer already gave directly, and — for a place question — the address
/// that the answer will rename.
///
/// Richer than the plain strings a `QuestionSet` carries, because the
/// answer has to do more than land in a paragraph: it renames places,
/// tags people, and records how the moment felt.
struct GuidedQuestion: Identifiable, Equatable, Sendable {
    /// What the question is about, which decides what its answer does to
    /// the day beyond becoming prose.
    enum Subject: Equatable, Sendable {
        case open
        /// A place whose name came back as a bare address; the answer
        /// renames it everywhere (`PlaceRenamer`).
        case place(rawName: String, latitude: Double?, longitude: Double?)
        case event(title: String)
        case photos
        /// Faces the phone counted in a shot — the answer says who they are.
        case peopleInPhoto(faceCount: Int)
        case activity
    }

    var id: String
    var text: String
    var subject: Subject = .open
    /// `PHAsset` local identifiers to show with the question, so the
    /// writer is looking at the actual photo while answering.
    var photoAssetIdentifiers: [String] = []
    /// Names already known because the writer wrote or tagged them, offered
    /// as chips. Tapping one writes the name into the answer *and* tags
    /// them on the day.
    var nameSuggestions: [String] = []

    /// The follow-up asked under every question so the entry carries the
    /// writer's emotional response and not just the facts. Nil only when
    /// the question itself is already about feelings.
    var feelingPrompt: String? = "How did that feel?"

    /// The place this question is about, whatever its name looks like. A
    /// place with a perfectly good name can still turn out to be somewhere
    /// the writer only walked past, so the options are offered either way.
    var placeSubject: (rawName: String, latitude: Double?, longitude: Double?)? {
        guard case let .place(rawName, latitude, longitude) = subject else { return nil }
        return (rawName, latitude, longitude)
    }

    /// The address this question's answer would rename, if any.
    var renamablePlace: (rawName: String, latitude: Double?, longitude: Double?)? {
        guard let place = placeSubject, PlaceNameResolver.looksLikeAddress(place.rawName) else { return nil }
        return place
    }
}

extension GuidedQuestion {
    /// The user's chosen question set, lifted into the same shape — days
    /// with nothing to go on still get the prompts they picked, and still
    /// get asked how each one felt.
    static func from(_ questionSet: QuestionSet) -> [GuidedQuestion] {
        questionSet.prompts.enumerated().map { index, prompt in
            GuidedQuestion(
                id: "\(questionSet.id).\(index)",
                text: prompt,
                feelingPrompt: feelingPrompt(for: prompt)
            )
        }
    }

    /// A question that already asks about feelings doesn't get asked about
    /// feelings again.
    static func feelingPrompt(for text: String, _ prompt: String = "How did that feel?") -> String? {
        let lowered = text.lowercased()
        let alreadyEmotional = ["feel", "feeling", "mood", "grateful", "smile"].contains { lowered.contains($0) }
        return alreadyEmotional ? nil : prompt
    }
}
