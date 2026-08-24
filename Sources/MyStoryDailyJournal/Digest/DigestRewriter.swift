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
        do {
            return try await attemptRewrite(of: ruleBasedText) ?? ruleBasedText
        } catch {
            return ruleBasedText
        }
        #else
        return ruleBasedText
        #endif
    }

    #if canImport(FoundationModels)
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
