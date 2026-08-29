import XCTest
import SwiftData
import MapKit
@testable import MyStoryDailyJournal

final class PlaceOptionsTests: XCTestCase {
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
        components.hour = 20
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func placeQuestion(_ rawName: String) -> GuidedQuestion {
        GuidedQuestion(
            id: "place.\(rawName)",
            text: "What's at \(rawName)?",
            subject: .place(rawName: rawName, latitude: 37.781, longitude: -122.416)
        )
    }

    // MARK: - The options themselves

    func testEveryKindNamesItselfForTheEntry() {
        XCTAssertEqual(PlaceKind.home.entryPhrase, "home")
        XCTAssertEqual(PlaceKind.comedyClub.entryPhrase, "the comedy club")
        XCTAssertEqual(PlaceKind.friendsPlace.entryPhrase, "a friend's place")
        XCTAssertEqual(PlaceKind.walkingPast.entryPhrase, "", "A place walked past is never named in the entry.")
        XCTAssertTrue(PlaceKind.options.contains(.walkingPast))
    }

    func testChoicesResolveToWhatTheEntryShouldSay() {
        XCTAssertEqual(PlaceChoice.kind(.home).confirmedName, "home")
        XCTAssertEqual(PlaceChoice.venue(name: "Cobb's", categoryLabel: "comedy club").confirmedName, "Cobb's")
        XCTAssertEqual(PlaceChoice.venue(name: "Cobb's", categoryLabel: "comedy club").displayName, "Cobb's · comedy club")
        XCTAssertNil(PlaceChoice.kind(.walkingPast).confirmedName)
        XCTAssertTrue(PlaceChoice.kind(.walkingPast).isPassingThrough)
        XCTAssertEqual(PlaceChoice.kind(.walkingPast).answerText, "Just walking past.")
    }

    // MARK: - What Maps calls a place

    func testMapsCategoriesBecomePlainWords() {
        XCTAssertEqual(PlaceLookup.label(for: .cafe), "café")
        XCTAssertEqual(PlaceLookup.label(for: .nightlife), "bar")
        XCTAssertNil(PlaceLookup.label(for: nil))
    }

    func testUnknownCategoriesFallBackToTheirOwnName() {
        XCTAssertEqual(PlaceLookup.humanized("MKPOICategoryMusicVenue"), "music venue")
        XCTAssertEqual(PlaceLookup.humanized("MKPOICategoryZoo"), "zoo")
        XCTAssertNil(PlaceLookup.humanized("MKPOICategory"))
    }

    // MARK: - Choosing an option settles the place

    @MainActor func testChoosingAKindNamesEvenAPlaceThatAlreadyHadAName() {
        let question = placeQuestion("Sunset District")
        let confirmations = GuidedAnswerApplier.placeConfirmations(
            questions: [question],
            responses: [GuidedResponse(question: question.text, answer: "At home.")],
            placeChoices: [.kind(.home)]
        )

        XCTAssertEqual(confirmations.count, 1)
        XCTAssertEqual(confirmations.first?.confirmedName, "home")
        XCTAssertEqual(confirmations.first?.kind, .home)
    }

    @MainActor func testATypedAnswerNeverRenamesAPlaceThatAlreadyHasAName() {
        let question = GuidedQuestion(
            id: "place.blueBottle",
            text: "You spent time at Blue Bottle — what were you doing there?",
            subject: .place(rawName: "Blue Bottle", latitude: nil, longitude: nil)
        )
        let confirmations = GuidedAnswerApplier.placeConfirmations(
            questions: [question],
            responses: [GuidedResponse(question: question.text, answer: "Met Dana for coffee")]
        )
        XCTAssertTrue(confirmations.isEmpty)
    }

    @MainActor func testAVenueFromMapsBecomesTheNameAndCarriesItsCategory() {
        let context = makeContext()
        let record = DayRecordRepository.record(for: makeDate(), in: context)
        record.bodyText = "Wednesday, March 4. Spent time at 915 Columbus Avenue."

        let visit = DaySignal(kind: .visit, timestamp: makeDate())
        visit.setPayload(VisitPayload(placeName: "915 Columbus Avenue", latitude: 37.781, longitude: -122.416, isFullAccuracy: true))
        visit.dayRecord = record
        context.insert(visit)
        record.signals = [visit]

        let question = placeQuestion("915 Columbus Avenue")
        let outcome = GuidedAnswerApplier.apply(
            questions: [question],
            responses: [GuidedResponse(question: question.text, answer: "Cobb's, the comedy club")],
            placeChoices: [.venue(name: "Cobb's Comedy Club", categoryLabel: "comedy club")],
            baseText: record.bodyText,
            to: record,
            in: context
        )

        XCTAssertEqual(outcome.renamedPlaces["915 Columbus Avenue"], "Cobb's Comedy Club")
        XCTAssertTrue(outcome.baseText.contains("Spent time at Cobb's Comedy Club."))
        let payload = visit.payload(as: VisitPayload.self)
        XCTAssertEqual(payload?.placeName, "Cobb's Comedy Club")
        XCTAssertEqual(payload?.categoryLabel, "comedy club")
    }

    // MARK: - Just walking past

    @MainActor func testWalkingPastLeavesTheStopOutOfTheStory() {
        let context = makeContext()
        let record = DayRecordRepository.record(for: makeDate(), in: context)
        record.bodyText = "Wednesday, March 4. Spent time at 2100 Geary Boulevard. Took one photo in the evening."

        let visit = DaySignal(kind: .visit, timestamp: makeDate())
        visit.setPayload(VisitPayload(placeName: "2100 Geary Boulevard", latitude: 37.781, longitude: -122.446, isFullAccuracy: true))
        visit.dayRecord = record
        context.insert(visit)
        record.signals = [visit]

        let question = placeQuestion("2100 Geary Boulevard")
        let outcome = GuidedAnswerApplier.apply(
            questions: [question],
            responses: [GuidedResponse(question: question.text, answer: "Just walking past.")],
            placeChoices: [.kind(.walkingPast)],
            baseText: record.bodyText,
            to: record,
            in: context
        )

        XCTAssertEqual(outcome.omittedPlaces, ["2100 Geary Boulevard"])
        XCTAssertFalse(outcome.baseText.contains("2100 Geary Boulevard"))
        XCTAssertTrue(outcome.baseText.contains("Took one photo in the evening."))
        XCTAssertEqual(visit.payload(as: VisitPayload.self)?.isPassingThrough, true)
        XCTAssertTrue(outcome.renamedPlaces.isEmpty, "A place walked past is never renamed or remembered.")
        XCTAssertNil(PlaceAliasStore.name(for: "2100 Geary Boulevard"))
    }

    func testRemovingMentionsKeepsTheRestOfTheEntry() {
        let text = "Wednesday. Spent time at 2100 Geary Boulevard. Rain, high around 18°."
        XCTAssertEqual(
            PlaceNameResolver.removingMentions(of: "2100 Geary Boulevard", in: text),
            "Wednesday. Rain, high around 18°."
        )
    }

    func testRemovingMentionsRatherThanEmptyingTheEntry() {
        let text = "Spent time at 2100 Geary Boulevard."
        XCTAssertEqual(PlaceNameResolver.removingMentions(of: "2100 Geary Boulevard", in: text), text)
    }

    // MARK: - What the digest writes

    func testDigestSkipsPlacesTheWriterOnlyWalkedPast() {
        let walked = DaySignal(kind: .visit, timestamp: makeDate())
        walked.setPayload(VisitPayload(
            placeName: "2100 Geary Boulevard",
            latitude: 0,
            longitude: 0,
            isFullAccuracy: true,
            isPassingThrough: true
        ))
        let visited = DaySignal(kind: .visit, timestamp: makeDate())
        visited.setPayload(VisitPayload(placeName: "home", latitude: 0, longitude: 0, isFullAccuracy: true))

        let text = DigestComposer.compose(date: makeDate(), signals: [walked, visited], placeAliases: [:])
        XCTAssertFalse(text.contains("2100 Geary Boulevard"))
        XCTAssertTrue(text.contains("Spent time at home."))
    }

    func testDigestSaysWhatKindOfPlaceAVenueIs() {
        let visit = DaySignal(kind: .visit, timestamp: makeDate())
        visit.setPayload(VisitPayload(
            placeName: "Cobb's",
            latitude: 0,
            longitude: 0,
            isFullAccuracy: true,
            categoryLabel: "comedy club"
        ))

        let text = DigestComposer.compose(date: makeDate(), signals: [visit], placeAliases: [:])
        XCTAssertTrue(text.contains("Spent time at Cobb's, the comedy club."))
    }

    func testDigestDoesNotRepeatACategoryTheNameAlreadySays() {
        let visit = DaySignal(kind: .visit, timestamp: makeDate())
        visit.setPayload(VisitPayload(
            placeName: "the comedy club",
            latitude: 0,
            longitude: 0,
            isFullAccuracy: true,
            categoryLabel: "comedy club"
        ))

        let text = DigestComposer.compose(date: makeDate(), signals: [visit], placeAliases: [:])
        XCTAssertTrue(text.contains("Spent time at the comedy club."))
    }

    func testAStopAlreadyWalkedPastIsNeverAskedAboutAgain() {
        let walked = DaySignal(kind: .visit, timestamp: makeDate())
        walked.setPayload(VisitPayload(
            placeName: "2100 Geary Boulevard",
            latitude: 0,
            longitude: 0,
            isFullAccuracy: true,
            isPassingThrough: true
        ))

        let questions = GuidedQuestionBuilder.questions(signals: [walked], aliases: [:])
        XCTAssertFalse(questions.contains { $0.text.contains("2100 Geary Boulevard") })
    }
}
