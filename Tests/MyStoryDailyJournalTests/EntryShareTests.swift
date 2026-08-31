import XCTest
import SwiftData
@testable import MyStoryDailyJournal

final class EntryShareTests: XCTestCase {
    private func makeContext() -> ModelContext {
        ModelContext(PersistenceController.makeContainer(inMemory: true))
    }

    private func makeDate() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 4
        components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func makeRecord(
        body: String,
        people: [String] = [],
        visit: (name: String, raw: String?, category: String?)? = nil,
        in context: ModelContext
    ) -> DayRecord {
        let record = DayRecord(date: makeDate(), source: .userWritten, bodyText: body)
        context.insert(record)
        record.people = people.map { name in
            let person = Person(name: name)
            context.insert(person)
            return person
        }
        if let visit {
            let signal = DaySignal(kind: .visit, timestamp: makeDate())
            signal.setPayload(VisitPayload(
                placeName: visit.name,
                latitude: 0,
                longitude: 0,
                isFullAccuracy: true,
                rawPlaceName: visit.raw,
                categoryLabel: visit.category
            ))
            signal.dayRecord = record
            context.insert(signal)
            record.signals = [signal]
        }
        try? context.save()
        return record
    }

    func testTheSharedCopyLeadsWithTheDate() {
        let text = ShareableEntry.text(
            body: "A good, slow day.",
            date: makeDate(),
            timeZoneIdentifier: "America/Los_Angeles"
        )
        XCTAssertTrue(text.hasPrefix("Wednesday, March 4, 2026"))
        XCTAssertTrue(text.hasSuffix("A good, slow day."))
    }

    func testTheDateCanBeLeftOff() {
        XCTAssertEqual(ShareableEntry.text(body: "  A good, slow day.  "), "A good, slow day.")
    }

    func testItFindsTheNamesThatAreActuallyInTheWords() {
        let context = makeContext()
        let record = makeRecord(
            body: "Coffee with Dana at Blue Bottle, then home.",
            people: ["Dana", "Priya"],
            visit: (name: "Blue Bottle", raw: "480 Larkin Street", category: "café"),
            in: context
        )

        let terms = ShareableEntry.sensitiveTerms(in: record, text: record.bodyText)
        XCTAssertTrue(terms.contains { $0.term == "Dana" && $0.kind == .person })
        XCTAssertTrue(terms.contains { $0.term == "Blue Bottle" && $0.replacement == "the café" })
        XCTAssertFalse(terms.contains { $0.term == "Priya" }, "Priya is tagged on the day but isn't in the text.")
        XCTAssertFalse(terms.contains { $0.term == "480 Larkin Street" }, "The address the entry no longer uses isn't in it.")
    }

    func testRedactingSwapsNamesForNeutralWordsWithoutTouchingTheEntry() {
        let context = makeContext()
        let record = makeRecord(
            body: "Coffee with Dana at Blue Bottle.",
            people: ["Dana"],
            visit: (name: "Blue Bottle", raw: nil, category: "café"),
            in: context
        )
        let terms = ShareableEntry.sensitiveTerms(in: record, text: record.bodyText)

        let shared = ShareableEntry.text(body: record.bodyText, redacting: terms)

        XCTAssertEqual(shared, "Coffee with a friend at the café.")
        XCTAssertEqual(record.bodyText, "Coffee with Dana at Blue Bottle.", "Sharing must never edit the journal.")
    }

    func testRedactingOnlyWhatTheWriterPicked() {
        let context = makeContext()
        let record = makeRecord(
            body: "Coffee with Dana at Blue Bottle.",
            people: ["Dana"],
            visit: (name: "Blue Bottle", raw: nil, category: "café"),
            in: context
        )
        let terms = ShareableEntry.sensitiveTerms(in: record, text: record.bodyText)
        let onlyThePerson = terms.filter { $0.kind == .person }

        XCTAssertEqual(
            ShareableEntry.text(body: record.bodyText, redacting: onlyThePerson),
            "Coffee with a friend at Blue Bottle."
        )
    }

    func testAPlaceWithNoCategoryLosesItsNameEntirely() {
        let context = makeContext()
        let record = makeRecord(
            body: "Spent the afternoon at Marchetti's.",
            visit: (name: "Marchetti's", raw: nil, category: nil),
            in: context
        )
        let terms = ShareableEntry.sensitiveTerms(in: record, text: record.bodyText)

        XCTAssertEqual(
            ShareableEntry.text(body: record.bodyText, redacting: terms),
            "Spent the afternoon at somewhere."
        )
    }
}
