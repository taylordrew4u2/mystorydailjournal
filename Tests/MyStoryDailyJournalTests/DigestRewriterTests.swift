import XCTest
@testable import MyStoryDailyJournal

final class DigestRewriterTests: XCTestCase {
    @MainActor
    func testRewriteIsANoOpWhenDisabled() async {
        SettingsStore.shared.digestRewriteEnabled = false
        let text = "Tuesday, March 4. Took nine photos."
        let result = await DigestRewriter.rewrite(ruleBasedText: text)
        XCTAssertEqual(result, text, "The rule-based text must be untouched when the setting is off.")
    }
}
