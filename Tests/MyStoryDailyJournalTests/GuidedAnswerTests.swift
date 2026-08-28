import XCTest
import SwiftData
@testable import MyStoryDailyJournal

final class GuidedAnswerTests: XCTestCase {
    /// Confirmed place names are remembered device-wide on purpose, so a
    /// test that confirms one has to put the store back afterwards.
    override func tearDown() {
        PlaceAliasStore.removeAll()
        super.tearDown()
    }

    private func makeContext() -> ModelContext {
        let container = PersistenceController.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    private func makeDate() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 4
        components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    // MARK: - The notes keep the questions

    func testTheLogKeepsEveryQuestionAnswerAndFeeling() {
        let block = GuidedAnswerLog.block(
            date: makeDate(),
            responses: [
                GuidedResponse(question: "What's at 12 Cypress Lane?", answer: "Blue Bottle", feeling: "happy"),
                GuidedResponse(question: "Anything else worth remembering?", answer: "", feeling: ""),
            ],
            timeZoneIdentifier: "America/Los_Angeles"
        )

        XCTAssertTrue(block.contains("Q: What's at 12 Cypress Lane?"))
        XCTAssertTrue(block.contains("A: Blue Bottle"))
        XCTAssertTrue(block.contains("Felt: happy"))
        XCTAssertFalse(block.contains("Anything else worth remembering?"), "Unanswered questions aren't worth logging.")
    }

    func testTheLogIsAppendedToWhateverWasAlreadyJotted() {
        let block = GuidedAnswerLog.block(
            date: makeDate(),
            responses: [GuidedResponse(question: "How did it go?", answer: "Well")]
        )

        let notes = GuidedAnswerLog.appending(block, to: "Bought coffee filters")
        XCTAssertTrue(notes.hasPrefix("Bought coffee filters"))
        XCTAssertTrue(notes.contains("A: Well"))

        XCTAssertEqual(GuidedAnswerLog.appending(block, to: notes), notes, "The same block must not pile up twice.")
    }

    func testAnEmptyRoundOfQuestionsLeavesTheNotesAlone() {
        let block = GuidedAnswerLog.block(date: makeDate(), responses: [GuidedResponse(question: "Q", answer: "  ")])
        XCTAssertEqual(block, "")
        XCTAssertEqual(GuidedAnswerLog.appending(block, to: "Just this"), "Just this")
    }

    func testTheFallbackSentenceKeepsTheFeelingWithTheAnswer() {
        XCTAssertEqual(GuidedResponse(question: "Q", answer: "Went to the market", feeling: "calm").sentence,
                       "Went to the market Felt calm.")
        XCTAssertEqual(GuidedResponse(question: "Q", answer: "", feeling: "tired").sentence, "Felt tired.")
        XCTAssertEqual(GuidedResponse(question: "Q", answer: "Just errands").sentence, "Just errands")
    }

    // MARK: - Answers change the day

    @MainActor func testAnsweringWhatIsAtAnAddressRenamesItEverywhere() {
        let context = makeContext()
        let record = DayRecordRepository.record(for: makeDate(), in: context)
        record.bodyText = "Wednesday, March 4. Spent time at 12 Cypress Lane."

        let visit = DaySignal(kind: .visit, timestamp: makeDate())
        visit.setPayload(VisitPayload(placeName: "12 Cypress Lane", latitude: 37.781, longitude: -122.416, isFullAccuracy: true))
        visit.dayRecord = record
        context.insert(visit)
        record.signals = [visit]

        let questions = [GuidedQuestion(
            id: "place",
            text: "What's at 12 Cypress Lane?",
            subject: .place(rawName: "12 Cypress Lane", latitude: 37.781, longitude: -122.416)
        )]
        let outcome = GuidedAnswerApplier.apply(
            questions: questions,
            responses: [GuidedResponse(question: questions[0].text, answer: "That's Blue Bottle, we got breakfast")],
            baseText: record.bodyText,
            to: record,
            in: context
        )

        XCTAssertEqual(outcome.renamedPlaces["12 Cypress Lane"], "Blue Bottle")
        XCTAssertTrue(outcome.baseText.contains("Spent time at Blue Bottle."))
        XCTAssertFalse(record.bodyText.contains("12 Cypress Lane"), "The address must not survive in the entry.")
        XCTAssertEqual(visit.payload(as: VisitPayload.self)?.placeName, "Blue Bottle")
        XCTAssertEqual(visit.payload(as: VisitPayload.self)?.rawPlaceName, "12 Cypress Lane")
    }

    @MainActor func testAShrugLeavesThePlaceNameAlone() {
        let questions = [GuidedQuestion(
            id: "place",
            text: "What's at 12 Cypress Lane?",
            subject: .place(rawName: "12 Cypress Lane", latitude: nil, longitude: nil)
        )]
        let confirmations = GuidedAnswerApplier.placeConfirmations(
            questions: questions,
            responses: [GuidedResponse(question: questions[0].text, answer: "no idea")]
        )
        XCTAssertTrue(confirmations.isEmpty)
    }

    @MainActor func testNamesInAnAnswerAreTaggedOnTheDayAndOnThePhoto() {
        let context = makeContext()
        let record = DayRecordRepository.record(for: makeDate(), in: context)

        let photo = DaySignal(kind: .photo, timestamp: makeDate())
        photo.setPayload(PhotoPayload(assetLocalIdentifier: "abc", isScreenshot: false, faceCount: 2))
        photo.dayRecord = record
        context.insert(photo)
        record.signals = [photo]

        let questions = [GuidedQuestion(
            id: "people",
            text: "There are 2 people in your 6:12 PM photo — who were you with?",
            subject: .peopleInPhoto(faceCount: 2),
            photoAssetIdentifiers: ["abc"],
            nameSuggestions: ["Dana", "Sam"]
        )]
        let outcome = GuidedAnswerApplier.apply(
            questions: questions,
            responses: [GuidedResponse(question: questions[0].text, answer: "Dana and her brother")],
            chosenNames: [[]],
            baseText: "",
            to: record,
            in: context
        )

        XCTAssertEqual(outcome.taggedPeople, ["Dana"])
        XCTAssertEqual(record.people?.map(\.name), ["Dana"])
        XCTAssertEqual(photo.payload(as: PhotoPayload.self)?.personNames, ["Dana"])
    }

    @MainActor func testTappedNameChipsCountAsAnAnswer() {
        let context = makeContext()
        let record = DayRecordRepository.record(for: makeDate(), in: context)

        let questions = [GuidedQuestion(
            id: "event",
            text: "How did \"Standup\" go, and who was with you?",
            subject: .event(title: "Standup"),
            nameSuggestions: ["Dana"]
        )]
        let outcome = GuidedAnswerApplier.apply(
            questions: questions,
            responses: [GuidedResponse(question: questions[0].text, answer: "Short one")],
            chosenNames: [["Dana"]],
            baseText: "",
            to: record,
            in: context
        )

        XCTAssertEqual(outcome.taggedPeople, ["Dana"])
    }

    func testOnlyNamesTheJournalKnowsAreLiftedOutOfAnAnswer() {
        let found = GuidedAnswerApplier.names(
            in: "Coffee with Dana, then dinner with Sam Rivera",
            among: ["Dana Chen", "Sam Rivera", "Priya"]
        )
        XCTAssertEqual(found, ["Dana Chen", "Sam Rivera"])
    }

    func testASubstringIsNotAName() {
        XCTAssertTrue(GuidedAnswerApplier.names(in: "Danced all evening", among: ["Dan"]).isEmpty)
    }
}
