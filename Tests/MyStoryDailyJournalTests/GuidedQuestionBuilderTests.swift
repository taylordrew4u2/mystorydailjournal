import XCTest
@testable import MyStoryDailyJournal

final class GuidedQuestionBuilderTests: XCTestCase {
    private func makeDate(hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 4
        components.hour = hour
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func visit(_ placeName: String, latitude: Double = 0, longitude: Double = 0, hour: Int = 9) -> DaySignal {
        let signal = DaySignal(kind: .visit, timestamp: makeDate(hour: hour))
        signal.setPayload(VisitPayload(placeName: placeName, latitude: latitude, longitude: longitude, isFullAccuracy: true))
        return signal
    }

    private func photo(
        identifier: String,
        hour: Int = 9,
        placeName: String? = nil,
        faceCount: Int = 0,
        isScreenshot: Bool = false
    ) -> DaySignal {
        let signal = DaySignal(kind: .photo, timestamp: makeDate(hour: hour))
        signal.setPayload(PhotoPayload(
            assetLocalIdentifier: identifier,
            isScreenshot: isScreenshot,
            placeName: placeName,
            faceCount: faceCount
        ))
        return signal
    }

    func testEveryAddressGetsItsOwnQuestion() {
        let signals = [
            visit("480 Larkin Street", hour: 9),
            visit("1200 Market Street", hour: 13),
            visit("77 Van Ness Avenue", hour: 18),
        ]

        let questions = GuidedQuestionBuilder.questions(signals: signals, aliases: [:])
        XCTAssertTrue(questions.contains { $0.text == "What's at 480 Larkin Street?" })
        XCTAssertTrue(questions.contains { $0.text == "What's at 1200 Market Street?" })
        XCTAssertTrue(questions.contains { $0.text == "What's at 77 Van Ness Avenue?" })
    }

    func testAConfirmedPlaceIsNeverAskedAboutAgain() {
        let signals = [visit("480 Larkin Street", latitude: 37.781, longitude: -122.416)]
        let aliases = [PlaceAliasStore.nameKey("480 Larkin Street"): "Blue Bottle"]

        let questions = GuidedQuestionBuilder.questions(signals: signals, aliases: aliases)
        XCTAssertFalse(questions.contains { $0.text.contains("480 Larkin Street") })
        XCTAssertTrue(questions.contains { $0.text == "You spent time at Blue Bottle — what were you doing there?" })
    }

    func testPlaceQuestionsCarryThePhotosTakenAroundThatTime() {
        let signals = [
            visit("480 Larkin Street", hour: 9),
            photo(identifier: "near", hour: 9),
            photo(identifier: "far", hour: 20),
        ]

        let questions = GuidedQuestionBuilder.questions(signals: signals, aliases: [:])
        let placeQuestion = questions.first { $0.text == "What's at 480 Larkin Street?" }
        XCTAssertEqual(placeQuestion?.photoAssetIdentifiers, ["near"])
    }

    func testFacesInAPhotoAreDescribedAndAskedAbout() {
        let signals = [photo(identifier: "abc", hour: 18, faceCount: 2)]

        let questions = GuidedQuestionBuilder.questions(signals: signals, aliases: [:])
        let peopleQuestion = questions.first { $0.text.contains("who were you with?") }
        XCTAssertNotNil(peopleQuestion, "A photo with faces in it should ask who they were.")
        XCTAssertTrue(peopleQuestion?.text.contains("2 people") == true)
        XCTAssertEqual(peopleQuestion?.photoAssetIdentifiers, ["abc"])
    }

    func testAPhotoWithConfirmedNamesIsNotAskedAboutAgain() {
        let signal = DaySignal(kind: .photo, timestamp: makeDate(hour: 18))
        signal.setPayload(PhotoPayload(
            assetLocalIdentifier: "abc",
            isScreenshot: false,
            faceCount: 2,
            personNames: ["Dana"]
        ))

        let questions = GuidedQuestionBuilder.questions(signals: [signal], aliases: [:])
        XCTAssertFalse(questions.contains { $0.text.contains("who were you with?") })
    }

    func testEventQuestionsDoNotOfferAttendeesAsAnswers() {
        let event = DaySignal(kind: .calendar, timestamp: makeDate(hour: 10))
        event.setPayload(CalendarPayload(eventIdentifier: "1", title: "Standup", attendeeNames: ["Dana", "Sam"]))

        let questions = GuidedQuestionBuilder.questions(signals: [event], aliases: [:])
        let eventQuestion = questions.first { $0.text.contains("Standup") }
        XCTAssertEqual(eventQuestion?.nameSuggestions, [])
    }

    func testEveryQuestionAsksHowItFeltUnlessItAlreadyDoes() {
        let questions = GuidedQuestionBuilder.questions(signals: [visit("480 Larkin Street")], aliases: [:])

        let feelingQuestion = questions.first { $0.text == "How were you feeling that day?" }
        XCTAssertNil(feelingQuestion?.feelingPrompt, "A question about feelings shouldn't ask about feelings again.")

        let placeQuestion = questions.first { $0.text == "What's at 480 Larkin Street?" }
        XCTAssertEqual(placeQuestion?.feelingPrompt, "How did being there feel?")
    }

    func testTheChosenQuestionSetAlsoAsksHowEachAnswerFelt() {
        let questions = GuidedQuestion.from(.gratitude)
        XCTAssertEqual(questions.count, QuestionSet.gratitude.prompts.count)
        XCTAssertEqual(questions.first?.text, QuestionSet.gratitude.prompts.first)
        XCTAssertNil(questions.first?.feelingPrompt, "\"What are you grateful for?\" is already an emotional question.")
        XCTAssertEqual(questions.last?.feelingPrompt, "How did that feel?")
    }

    func testDaysWithNothingToGoOnStillGetTheOpenQuestions() {
        let questions = GuidedQuestionBuilder.questions(signals: [], aliases: [:])
        XCTAssertEqual(questions.map(\.text), [
            "How were you feeling that day?",
            "Anything else worth remembering?",
        ])
    }

    func testContinuationQuestionsKeepGoingAfterTheInitialPrompts() {
        let responses = (0..<8).map { index in
            GuidedResponse(question: "Q\(index)", answer: "A\(index)")
        }

        let next = GuidedQuestionBuilder.continuationQuestion(after: responses, signals: [])

        XCTAssertFalse(next.text.isEmpty)
        XCTAssertTrue(next.id.hasPrefix("open.continue."))
    }

    func testContinuationQuestionsDoNotImmediatelyRepeat() {
        let questions = (0..<24).map { count in
            let responses = (0..<count).map { index in
                GuidedResponse(question: "Q\(index)", answer: "A\(index)")
            }
            return GuidedQuestionBuilder.continuationQuestion(after: responses, signals: []).text
        }

        XCTAssertEqual(Set(questions).count, questions.count)
    }

    func testContinuationQuestionsUseMovementWithoutRawStepCounts() {
        let activity = DaySignal(kind: .activity, timestamp: makeDate())
        activity.setPayload(ActivityPayload(stepCount: 44_000, distanceMeters: 32_000, workoutSummaries: []))
        let responses = [
            GuidedResponse(question: "First", answer: "One"),
            GuidedResponse(question: "Second", answer: "Two"),
        ]

        let next = GuidedQuestionBuilder.continuationQuestion(after: responses, signals: [activity])

        XCTAssertTrue(next.text.contains("movement"))
        XCTAssertFalse(next.text.contains("44,000"))
        XCTAssertFalse(next.text.contains("steps"))
    }

    func testScreenshotsAreNeverTheSubjectOfAPhotoQuestion() {
        let signals = [photo(identifier: "shot", hour: 11, isScreenshot: true)]
        let questions = GuidedQuestionBuilder.questions(signals: signals, aliases: [:])
        let photoQuestion = questions.first { $0.text.contains("photo") }
        XCTAssertEqual(photoQuestion?.photoAssetIdentifiers, ["shot"], "With only screenshots, they're all there is to show.")
    }
}
