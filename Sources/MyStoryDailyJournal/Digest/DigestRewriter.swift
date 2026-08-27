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
    static func rewrite(ruleBasedText: String) async -> String {
        guard await SettingsStore.shared.digestRewriteEnabled else { return ruleBasedText }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return ruleBasedText }
        do {
            return try await attemptRewrite(of: ruleBasedText) ?? ruleBasedText
        } catch {
            return ruleBasedText
        }
        #else
        return ruleBasedText
        #endif
    }

    /// Weaves guided-question answers into one coherent first-person entry:
    /// with `digest` when refining an auto-generated day, or from the
    /// answers alone for a fresh guided entry. The contract is *seamless*
    /// integration — every answer, however short, offhand, or random, must
    /// surface in the result, placed where it belongs in the story rather
    /// than stapled on at the end. Returns `nil` whenever the on-device
    /// model can't help (unavailable hardware, thrown error, empty
    /// response) — the caller keeps the plain paragraph composition as
    /// fallback. Not gated behind `digestRewriteEnabled`: the user
    /// explicitly asked for this by walking through the questions.
    static func weaveEntry(digest: String?, questionsAndAnswers: [(question: String, answer: String)]) async -> String? {
        let answered = questionsAndAnswers.filter {
            !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !answered.isEmpty else { return nil }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return nil }
        let transcript = answered
            .map { "Q: \($0.question)\nA: \($0.answer)" }
            .joined(separator: "\n")

        var prompt = """
        Write one natural, first-person journal entry from the material \
        below.

        Rules:
        - Every single answer must appear in the entry, including short, \
        offhand, or seemingly unrelated remarks — nothing the writer said \
        may be dropped, and each detail belongs where it naturally fits in \
        the story, never tacked on at the end.
        - Keep every fact exactly as given: people, places, event names, \
        numbers, feelings. Do not invent anything that isn't stated.
        - Never mention the questions, or that any of this came from a \
        question-and-answer session. The result reads as if the writer \
        wrote it in one sitting.
        - Plain text only. No emoji, no headings, no lists.
        """
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
    private static func attemptRewrite(of text: String) async throws -> String? {
        guard case .available = SystemLanguageModel.default.availability else {
            return nil
        }

        let session = LanguageModelSession()
        let prompt = """
        Rewrite this daily journal summary in a warmer, more natural voice. \
        Keep every fact exactly as given — don't add or remove anything, \
        just make it read less like a list. No emoji, plain text only.

        \(text)
        """
        let response = try await session.respond(to: prompt)
        let rewritten = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return rewritten.isEmpty ? nil : rewritten
    }
    #endif
}
