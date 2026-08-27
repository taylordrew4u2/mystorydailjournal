import Foundation

/// Default entry mode set in the wizard (build spec §6, §7). Always
/// overridable per entry regardless of this default.
enum WritingStyle: String, CaseIterable, Identifiable, Codable {
    case freeform
    case guided
    case askEachTime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .freeform: "Freeform"
        case .guided: "Guided"
        case .askEachTime: "Ask me each time"
        }
    }
}

/// The voice the on-device model writes in — applied to digest rewrites
/// and guided-answer weaving alike. `natural` adds no instruction, so the
/// model's default voice (and the rule-based fallback) are unchanged.
enum WritingTone: String, CaseIterable, Identifiable, Codable {
    case natural
    case warm
    case reflective
    case upbeat
    case matterOfFact
    case poetic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .natural: "Natural"
        case .warm: "Warm"
        case .reflective: "Reflective"
        case .upbeat: "Upbeat"
        case .matterOfFact: "Matter-of-fact"
        case .poetic: "Poetic"
        }
    }

    /// The sentence appended to rewrite prompts; nil adds nothing.
    var promptInstruction: String? {
        switch self {
        case .natural: nil
        case .warm: "Write in a warm, affectionate voice."
        case .reflective: "Write in a calm, reflective, thoughtful voice."
        case .upbeat: "Write in a bright, upbeat, energetic voice."
        case .matterOfFact: "Write plainly and matter-of-factly, without flourishes."
        case .poetic: "Write with a gently lyrical, poetic touch — without inventing any new facts."
        }
    }
}

/// A named sequence of 3-5 short reflective prompts, composed into the
/// entry body once all are answered. See build spec §6.
struct QuestionSet: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var prompts: [String]

    static let simpleRecap = QuestionSet(
        id: "simpleRecap",
        name: "Simple recap",
        prompts: [
            "What's one thing that happened today?",
            "How are you feeling, in a few words?",
            "Anything else worth remembering?",
        ]
    )

    static let gratitude = QuestionSet(
        id: "gratitude",
        name: "Gratitude",
        prompts: [
            "What are you grateful for today?",
            "What made you smile?",
            "One small win, however small?",
        ]
    )

    static let starterSets: [QuestionSet] = [.simpleRecap, .gratitude]
}
