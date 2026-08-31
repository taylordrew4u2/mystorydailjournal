import XCTest
import SwiftData
@testable import MyStoryDailyJournal

final class LearningLoopTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "LearningLoopTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeContext() -> ModelContext {
        ModelContext(PersistenceController.makeContainer(inMemory: true))
    }

    private func makeDate(daysAgo: Int = 0) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 10
        components.hour = 20
        let anchor = calendar.date(from: components)!
        return calendar.date(byAdding: .day, value: -daysAgo, to: anchor)!
    }

    @discardableResult
    private func tag(_ name: String, onDays count: Int, in context: ModelContext) -> Person {
        let person = Person(name: name)
        context.insert(person)
        for day in 0..<count {
            let record = DayRecord(date: makeDate(daysAgo: day), source: .userWritten, bodyText: "A day.")
            context.insert(record)
            record.people = [person]
        }
        try? context.save()
        return person
    }

    // MARK: - The pen's questions

    func testItAsksAboutWhoeverTurnsUpMost() {
        let context = makeContext()
        tag("Priya", onDays: 2, in: context)
        tag("Dana", onDays: 9, in: context)

        let queue = RelationshipPrompter.peopleToAskAbout(in: context, now: makeDate())

        XCTAssertEqual(queue.map(\.name), ["Dana", "Priya"], "Getting the most-present person right fixes the most entries.")
    }

    func testItDoesNotAskAboutSomeoneAlreadyDescribed() {
        let context = makeContext()
        let dana = tag("Dana", onDays: 9, in: context)
        RelationshipPrompter.describe(dana, relationship: "My sister", in: context)

        XCTAssertTrue(RelationshipPrompter.peopleToAskAbout(in: context, now: makeDate()).isEmpty)
        XCTAssertFalse(RelationshipPrompter.hasQuestions(in: context, now: makeDate()))
    }

    func testSkippingSomeoneMeansLaterNotNever() {
        let context = makeContext()
        let dana = tag("Dana", onDays: 9, in: context)
        let now = makeDate()
        RelationshipPrompter.skip(dana, now: now, in: context)

        XCTAssertTrue(
            RelationshipPrompter.peopleToAskAbout(in: context, now: now).isEmpty,
            "Skipping shouldn't put them straight back at the front."
        )
        let muchLater = now.addingTimeInterval(RelationshipPrompter.skipInterval + 60)
        XCTAssertEqual(
            RelationshipPrompter.peopleToAskAbout(in: context, now: muchLater).map(\.name),
            ["Dana"]
        )
    }

    func testItNeverAsksAboutAPersonNoDayMentions() {
        let context = makeContext()
        let stranger = Person(name: "Someone")
        context.insert(stranger)
        try? context.save()

        XCTAssertTrue(RelationshipPrompter.peopleToAskAbout(in: context, now: makeDate()).isEmpty)
    }

    func testWhatTheWriterSaidAboutSomeoneIsWhatTheWritingGets() {
        let context = makeContext()
        let dana = tag("Dana", onDays: 5, in: context)
        RelationshipPrompter.describe(
            dana,
            relationship: "My sister",
            pronouns: "she/her",
            note: "lives in Oakland",
            in: context
        )

        XCTAssertEqual(dana.descriptionForWriting, "My sister; goes by she/her; lives in Oakland")
        XCTAssertTrue(dana.isDescribed)
        XCTAssertNotNil(dana.askedAt)

        ProfileLearner.learn(in: context, now: makeDate(), defaults: defaults)
        let fact = ((try? context.fetch(FetchDescriptor<ProfileFact>())) ?? [])
            .first { $0.kind == .person && $0.subject == "Dana" }
        XCTAssertTrue(fact?.detail.contains("My sister") == true, "Got: \(fact?.detail ?? "none")")
    }

    // MARK: - Corrections

    func testACorrectionIsKeptAsAnInstruction() {
        let context = makeContext()
        let fact = EntryCorrection.record("Alex is my brother, not a coworker.", in: context)

        XCTAssertEqual(fact?.kind, .correction)
        XCTAssertEqual(fact?.detail, "Alex is my brother, not a coworker.")
        XCTAssertEqual(EntryCorrection.all(in: context).count, 1)
    }

    func testAnEmptyComplaintIsNotACorrection() {
        let context = makeContext()
        XCTAssertNil(EntryCorrection.record("   ", in: context))
        XCTAssertTrue(EntryCorrection.all(in: context).isEmpty)
    }

    func testSayingTheSameThingTwiceSharpensItRatherThanStackingIt() {
        let context = makeContext()
        EntryCorrection.record("Don't say I was productive.", in: context)
        EntryCorrection.record("don't say i was productive", in: context)

        let corrections = EntryCorrection.all(in: context)
        XCTAssertEqual(corrections.count, 1)
        XCTAssertEqual(corrections.first?.observationCount, 2)
    }

    func testCorrectionsOutrankEverythingTheAppWorkedOutItself() {
        let context = makeContext()
        let correction = ProfileFact(
            kind: .correction,
            subject: "tone",
            detail: "Never call my days productive.",
            observationCount: 1
        )
        let voice = ProfileFact(kind: .voice, subject: "entry length", detail: "Keeps entries short.")
        let person = ProfileFact(kind: .person, subject: "Dana", detail: "Dana — appears on 40 days.", observationCount: 40)
        [correction, voice, person].forEach(context.insert)

        let chosen = ProfileBrief.select(
            from: [voice, person, correction],
            cues: ProfileBrief.Cues(people: ["Dana"]),
            budget: 40
        )

        XCTAssertEqual(chosen.first?.kind, .correction, "A correction is the writer overruling the app.")
    }

    func testTheBriefLabelsCorrectionsAsInstructions() {
        let correction = ProfileFact(kind: .correction, subject: "tone", detail: "Never call my days productive.")
        let rendered = ProfileBrief.render([correction])
        XCTAssertTrue(rendered?.contains("follow these exactly") == true, "Got: \(rendered ?? "nil")")
        XCTAssertTrue(rendered?.contains("Never call my days productive.") == true)
    }
}
