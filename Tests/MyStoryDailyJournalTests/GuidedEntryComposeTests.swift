import XCTest
@testable import MyStoryDailyJournal

final class GuidedEntryComposeTests: XCTestCase {
    @MainActor func testComposeJoinsNonEmptyAnswersAsParagraphs() {
        let composed = GuidedEntryView.compose(answers: ["Went hiking.", "", "Tired but good."])
        XCTAssertEqual(composed, "Went hiking.\n\nTired but good.")
    }

    @MainActor func testComposeTrimsWhitespace() {
        let composed = GuidedEntryView.compose(answers: ["  Rested today.  "])
        XCTAssertEqual(composed, "Rested today.")
    }

    @MainActor func testComposeOfAllEmptyAnswersIsEmptyString() {
        let composed = GuidedEntryView.compose(answers: ["", "   ", ""])
        XCTAssertEqual(composed, "")
    }
}
