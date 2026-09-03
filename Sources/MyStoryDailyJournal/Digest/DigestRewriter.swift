import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Optional on-device rewrite of the rule-based digest into a more natural
/// voice (§9, §13 M10). Default off, gated behind
/// `SettingsStore.digestRewriteEnabled`, and the rule-based text from
/// `DigestComposer` always stays the fallback — this never becomes the
/// only way a digest gets produced.
///
/// **Version-sensitive and best-effort** (§18): the Foundation Models
/// framework is new enough that its exact type/method names here
/// (`SystemLanguageModel`, `LanguageModelSession.respond(to:)`) need
/// confirming against the SDK this actually builds against, and its
/// hardware/OS availability is narrow. Any failure — unavailable model,
/// thrown error, empty response — falls straight back to the rule-based
/// text rather than surfacing an error, since this is a "nicer to have,"
/// not a data path.
enum DigestRewriter {
    private static let purpose = """
    Purpose:
    - You are the private writing layer of one person's journal. Your job is \
    to help them remember their own life in words that feel like theirs.
    - Treat phone signals, user-started imports, imported profile writing, \
    and learned patterns as clues, not as the story. Turn them into human \
    context only when they help explain what the day felt like.
    - Never write like a tracker, report, assistant, or app. Do not mention \
    data sources, sensors, imports, prompts, models, or profile learning.
    - Preserve privacy: write only about this writer's day. Do not imply \
    contact with, discovery of, tracking of, or knowledge about outside \
    people unless the writer explicitly supplied that detail.
    - Be curious but grounded. If something is unclear, the app should ask \
    the writer later; the entry itself must not guess.
    """

    static func rewrite(ruleBasedText: String, profile: String? = nil) async -> String {
        guard await SettingsStore.shared.digestRewriteEnabled else { return ruleBasedText }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return ruleBasedText }
        do {
            return try await attemptRewrite(of: ruleBasedText, profile: profile) ?? ruleBasedText
        } catch {
            return ruleBasedText
        }
        #else
        return ruleBasedText
        #endif
    }

    /// Weaves guided-question answers into one coherent first-person entry:
    /// with `digest` when refining an auto-generated day, or from the
    /// answers alone for a fresh guided entry. Every answer, however short,
    /// offhand, or random, must surface in the result, placed where it
    /// belongs in the story rather than stapled on at the end, and each
    /// answer's stated feeling has to shape how that moment is told.
    /// Returns `nil` whenever the on-device model can't help (unavailable
    /// hardware, thrown error, empty response) — the caller keeps the plain
    /// paragraph composition as fallback. Not gated behind
    /// `digestRewriteEnabled`: the user explicitly asked for this by
    /// walking through the questions.
    static func weaveEntry(
        digest: String?,
        responses: [GuidedResponse],
        omitPlaces: [String] = [],
        profile: String? = nil
    ) async -> String? {
        let answered = responses.filter(\.isAnswered)
        guard !answered.isEmpty else { return nil }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return nil }
        let transcript = answered
            .map { response in
                var lines = ["Q: \(response.question)"]
                if !response.trimmedAnswer.isEmpty {
                    lines.append("A: \(response.trimmedAnswer)")
                }
                if !response.trimmedFeeling.isEmpty {
                    lines.append("How it felt: \(response.trimmedFeeling)")
                }
                return lines.joined(separator: "\n")
            }
            .joined(separator: "\n")

        var prompt = """
        \(purpose)

        Write one natural, first-person journal entry from the material \
        below.

        Rules:
        - Every single answer must appear in the entry, including short, \
        offhand, or seemingly unrelated remarks — nothing the writer said \
        may be dropped, and each detail belongs where it naturally fits in \
        the story, never tacked on at the end.
        - Make it sound written by a real person, not polished, poetic, or \
        like a perfect recap. Use first person, contractions when natural, \
        and small connective phrases. Keep the language plain and specific: \
        no lyrical imagery, no dramatic phrasing, no "the day held..." or \
        "a thread ran through..." style lines. Vary sentence openings so the entry \
        does not become "I... I... I..." or a stack of identical clauses; \
        avoid generic lines like "today was a good day" unless the writer \
        actually said that.
        - Keep every fact exactly as given: people, places, event names, \
        numbers, feelings. Do not invent anything that isn't stated.
        - Where the writer said how something felt, let that feeling shape \
        how that part of the day is told — in the writing itself, never as \
        a label or a separate line about emotions.
        - Places have names: if the material gives a venue name for a \
        street address, use the name and never write the address.
        - Never mention the questions, or that any of this came from a \
        question-and-answer session. The result reads as if the writer \
        wrote it in one sitting.
        - Plain text only. No emoji, no headings, no lists.
        """
        if !omitPlaces.isEmpty {
            prompt += """

        - The writer was only walking past these places, so they are not \
        part of the day and must not appear in the entry at all: \
        \(omitPlaces.joined(separator: ", ")).
        """
        }
        if let toneInstruction = await SettingsStore.shared.writingTone.promptInstruction {
            prompt += "\n- \(toneInstruction)"
        }
        if let profile {
            prompt += """


            About the writer, learned on-device from their own journal — use \
            it to match their voice and to know who and what they mean, never \
            state any of it as something that happened today. Anything under \
            "Corrections" is a standing instruction from the writer about how \
            to write their days; follow it exactly, even where it overrides \
            the rules above:
            \(profile)
            """
        }
        if let digest, !digest.isEmpty {
            prompt += """


            What the phone observed about the day:
            \(digest)
            """
        }
        prompt += """


        The writer's own answers:
        \(transcript)
        """

        do {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let response = try await LanguageModelSession().respond(to: prompt)
            let rewritten = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return rewritten.isEmpty ? nil : rewritten
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func attemptRewrite(of text: String, profile: String? = nil) async throws -> String? {
        guard case .available = SystemLanguageModel.default.availability else {
            return nil
        }

        let session = LanguageModelSession()
        var prompt = """
        \(purpose)

        Rewrite this daily journal summary in a plain, natural voice. \
        Keep every fact exactly as given — don't add or remove anything, \
        just make it read less like a list. It should sound like the writer \
        jotting down what they remember, not an assistant recapping sensor \
        output. Use first person, contractions where they fit, and plain \
        human phrasing. Do not make it poetic, lyrical, dramatic, or overly \
        polished. Avoid lines like "the day held..." or "a thread ran through..." \
        unless the writer used those exact words. Vary sentence openings \
        and sentence lengths so it does not read like the same template repeated. Raw metrics are \
        clues, not prose: \
        avoid exact step counts or tracker-like measurements unless the \
        writer explicitly wrote them. Do not explain every source just \
        because it exists. No emoji, plain text only.
        """
        if let toneInstruction = await SettingsStore.shared.writingTone.promptInstruction {
            prompt += " \(toneInstruction)"
        }
        if let profile {
            prompt += """


            About the writer, learned on-device from their own journal — use \
            it to match their voice and to know who and what they mean, never \
            state any of it as something that happened today. Anything under \
            "Corrections" is a standing instruction from the writer about how \
            to write their days; follow it exactly, even where it overrides \
            the rules above:
            \(profile)
            """
        }
        prompt += "\n\n\(text)"
        let response = try await session.respond(to: prompt)
        let rewritten = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return rewritten.isEmpty ? nil : rewritten
    }
    #endif
}
