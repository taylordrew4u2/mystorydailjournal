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
