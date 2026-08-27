import Foundation
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A compact, always-current picture of the writer, learned entirely
/// on-device from their own journal: who they write about, their recurring
/// themes, and how long they like their entries. Rebuilt fresh from the
/// last 30 user-written days every time it's used — the app keeps learning
/// as the journal grows, and nothing about this ever leaves the phone.
enum WriterProfile {
    static func summary(in context: ModelContext) -> String? {
        let userWritten = DayRecordSource.userWritten.rawValue
        let converted = DayRecordSource.converted.rawValue
        var descriptor = FetchDescriptor<DayRecord>(
            predicate: #Predicate { $0.sourceRaw == userWritten || $0.sourceRaw == converted },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        guard let records = try? context.fetch(descriptor), !records.isEmpty else { return nil }

        var parts: [String] = []

        let peopleCounts = records
            .flatMap { $0.people ?? [] }
            .reduce(into: [String: Int]()) { $0[$1.name, default: 0] += 1 }
        let topPeople = peopleCounts.sorted { $0.value > $1.value }.prefix(4).map(\.key)
        if !topPeople.isEmpty {
            parts.append("People who often appear in their life: \(topPeople.joined(separator: ", ")).")
        }

        let tagCounts = records
            .flatMap { $0.tags ?? [] }
            .reduce(into: [String: Int]()) { $0[$1.name, default: 0] += 1 }
        let topTags = tagCounts.sorted { $0.value > $1.value }.prefix(5).map(\.key)
        if !topTags.isEmpty {
            parts.append("Recurring themes in their journal: \(topTags.joined(separator: ", ")).")
        }

        let averageLength = records.map(\.bodyText.count).reduce(0, +) / records.count
        switch averageLength {
        case ..<200: parts.append("They keep entries short and to the point.")
        case ..<800: parts.append("They usually write a few unhurried paragraphs.")
        default: parts.append("They like long, detailed entries.")
        }

        return parts.joined(separator: " ")
    }
}

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
    static func rewrite(ruleBasedText: String, writerProfile: String? = nil) async -> String {
        guard await SettingsStore.shared.digestRewriteEnabled else { return ruleBasedText }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return ruleBasedText }
        do {
            return try await attemptRewrite(of: ruleBasedText, writerProfile: writerProfile) ?? ruleBasedText
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
    static func weaveEntry(digest: String?, questionsAndAnswers: [(question: String, answer: String)], writerProfile: String? = nil) async -> String? {
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
        if let toneInstruction = await SettingsStore.shared.writingTone.promptInstruction {
            prompt += "\n- \(toneInstruction)"
        }
        if let writerProfile {
            prompt += """


            About the writer, learned on-device from their journal — use it \
            only to match their voice and what they care about, never state \
            it as new facts:
            \(writerProfile)
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
    private static func attemptRewrite(of text: String, writerProfile: String? = nil) async throws -> String? {
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
        if let writerProfile {
            prompt += """


            About the writer, learned on-device from their journal — use it \
            only to match their voice, never state it as new facts:
            \(writerProfile)
            """
        }
        prompt += "\n\n\(text)"
        let response = try await session.respond(to: prompt)
        let rewritten = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return rewritten.isEmpty ? nil : rewritten
    }
    #endif
}
