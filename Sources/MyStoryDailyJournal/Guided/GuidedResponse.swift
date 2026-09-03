import Foundation

/// One answered guided question: what was asked, what the writer said, and
/// how they said it felt. The feeling travels with the answer everywhere —
/// into the woven entry, and into the notes the day keeps.
struct GuidedResponse: Equatable, Sendable {
    var question: String
    var answer: String
    var feeling: String = ""

    var trimmedAnswer: String { answer.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedFeeling: String { feeling.trimmingCharacters(in: .whitespacesAndNewlines) }

    var isAnswered: Bool { !trimmedAnswer.isEmpty || !trimmedFeeling.isEmpty }

    /// The plain-text form used when the on-device model can't run — the
    /// answer, with the feeling kept rather than dropped.
    var sentence: String {
        switch (trimmedAnswer.isEmpty, trimmedFeeling.isEmpty) {
        case (true, true): ""
        case (false, true): trimmedAnswer
        case (true, false): "It felt \(trimmedFeeling)."
        case (false, false): "\(trimmedAnswer) It felt \(trimmedFeeling)."
        }
    }
}

/// Writes the guided questions and answers into the day's Notes panel, so
/// the notes hold the raw material — every question asked, every answer,
/// every feeling — next to whatever the writer jotted themselves. The
/// diary panel gets the woven prose; this is the record it was woven from.
enum GuidedAnswerLog {
    /// A dated block of everything answered this round, or "" when nothing
    /// was answered.
    static func block(
        date: Date,
        responses: [GuidedResponse],
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) -> String {
        let answered = responses.filter(\.isAnswered)
        guard !answered.isEmpty else { return "" }

        var style = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day()
        style.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current

        var lines = ["Guided questions — \(date.formatted(style))"]
        for response in answered {
            lines.append("Q: \(response.question)")
            if !response.trimmedAnswer.isEmpty {
                lines.append("A: \(response.trimmedAnswer)")
            }
            if !response.trimmedFeeling.isEmpty {
                lines.append("Felt: \(response.trimmedFeeling)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Appends a block to the existing notes without ever replacing them —
    /// the scratchpad is never consumed (§ Notes panel contract). Answering
    /// the same questions twice without changing anything doesn't duplicate
    /// the block.
    static func appending(_ block: String, to notes: String) -> String {
        let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBlock.isEmpty else { return notes }
        let existing = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !existing.isEmpty else { return trimmedBlock }
        guard !existing.contains(trimmedBlock) else { return notes }
        return existing + "\n\n" + trimmedBlock
    }
}
