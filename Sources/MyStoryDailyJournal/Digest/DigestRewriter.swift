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
    /// answers alone for a fresh guided entry. The contract is *seamless*
    /// integration — every answer, however short, offhand, or random, must
    /// surface in the result, placed where it belongs in the story rather
    /// than stapled on at the end, and each answer's stated feeling has to
    /// color how that moment is told. Returns `nil` whenever the on-device
    /// model can't help (unavailable hardware, thrown error, empty
    /// response) — the caller keeps the plain paragraph composition as
    /// fallback. Not gated behind `digestRewriteEnabled`: the user
    /// explicitly asked for this by walking through the questions.
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
        Write one natural, first-person journal entry from the material \
        below.

        Rules:
        - Every single answer must appear in the entry, including short, \
        offhand, or seemingly unrelated remarks — nothing the writer said \
        may be dropped, and each detail belongs where it naturally fits in \
        the story, never tacked on at the end.
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
            state any of it as something that happened today:
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
        Rewrite this daily journal summary in a warmer, more natural voice. \
        Keep every fact exactly as given — don't add or remove anything, \
        just make it read less like a list. No emoji, plain text only.
        """
        if let toneInstruction = await SettingsStore.shared.writingTone.promptInstruction {
            prompt += " \(toneInstruction)"
        }
        if let profile {
            prompt += """


            About the writer, learned on-device from their own journal — use \
            it to match their voice and to know who and what they mean, never \
            state any of it as something that happened today:
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
