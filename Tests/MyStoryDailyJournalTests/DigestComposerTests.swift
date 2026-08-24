import XCTest
@testable import MyStoryDailyJournal

final class DigestComposerTests: XCTestCase {
    private func makeDate() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 4
        components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    func testComposeWithNoSignalsStillProducesAHeadline() {
        let text = DigestComposer.compose(date: makeDate(), signals: [])
        XCTAssertTrue(text.contains("Wednesday"))
        XCTAssertTrue(text.contains("No signals were available"))
    }

    func testComposeIsDeterministicForTheSameInputs() {
        let date = makeDate()
        let signals = makeMixedSignals()

        let first = DigestComposer.compose(date: date, signals: signals)
        let second = DigestComposer.compose(date: date, signals: signals)

        XCTAssertEqual(first, second)
    }

    func testComposeIncludesEachAvailableSignalKind() {
        let text = DigestComposer.compose(date: makeDate(), signals: makeMixedSignals())

        XCTAssertTrue(text.contains("Flatiron"))
        XCTAssertTrue(text.contains("calendar event"))
        XCTAssertTrue(text.contains("photo"))
        XCTAssertTrue(text.contains("steps"))
        XCTAssertTrue(text.contains("Rain"))
    }

    func testComposeIncludesFileWatchClause() {
        let signal = DaySignal(kind: .fileWatch, timestamp: makeDate())
        signal.setPayload(FileWatchPayload(fileName: "notes.txt", folderName: "Journal"))

        let text = DigestComposer.compose(date: makeDate(), signals: [signal])
        XCTAssertTrue(text.contains("One new file in Journal"))
    }

    func testComposeIncludesMediaClause() {
        let signal = DaySignal(kind: .media, timestamp: makeDate())
        signal.setPayload(MediaPayload(titles: ["A Song"]))

        let text = DigestComposer.compose(date: makeDate(), signals: [signal])
        XCTAssertTrue(text.contains("Listened to \"A Song\""))
    }

    func testComposeOmitsClausesForMissingSignalKinds() {
        let signal = DaySignal(kind: .calendar, timestamp: makeDate())
        signal.setPayload(CalendarPayload(eventIdentifier: "1", title: "Standup", attendeeNames: []))

        let text = DigestComposer.compose(date: makeDate(), signals: [signal])

        XCTAssertTrue(text.contains("One calendar event"))
        XCTAssertFalse(text.contains("steps"))
        XCTAssertFalse(text.contains("photo"))
    }

    private func makeMixedSignals() -> [DaySignal] {
        let date = makeDate()

        let visit = DaySignal(kind: .visit, timestamp: date)
        visit.setPayload(VisitPayload(placeName: "Flatiron", latitude: 0, longitude: 0, isFullAccuracy: false))

        let event = DaySignal(kind: .calendar, timestamp: date)
        event.setPayload(CalendarPayload(eventIdentifier: "1", title: "Standup", attendeeNames: ["Alex"]))

        let photo = DaySignal(kind: .photo, timestamp: date)
        photo.setPayload(PhotoPayload(assetLocalIdentifier: "abc", isScreenshot: false))

        let activity = DaySignal(kind: .activity, timestamp: date)
        activity.setPayload(ActivityPayload(stepCount: 11400, distanceMeters: 9000, workoutSummaries: []))

        let weather = DaySignal(kind: .weather, timestamp: date)
        weather.setPayload(WeatherPayload(conditionDescription: "Rain", highTemperatureCelsius: 18, lowTemperatureCelsius: 10))

        return [visit, event, photo, activity, weather]
    }
}
