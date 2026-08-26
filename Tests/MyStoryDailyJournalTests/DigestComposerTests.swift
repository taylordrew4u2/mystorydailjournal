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
        XCTAssertTrue(text.contains("Standup"))
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

        XCTAssertTrue(text.contains("Standup"))
        XCTAssertFalse(text.contains("steps"))
        XCTAssertFalse(text.contains("photo"))
    }

    func testCalendarClauseNamesEventTimeAndPlace() {
        let signal = DaySignal(kind: .calendar, timestamp: makeDate())
        signal.setPayload(CalendarPayload(
            eventIdentifier: "1",
            title: "Dinner with the team",
            attendeeNames: [],
            location: "Luigi's Trattoria"
        ))

        let text = DigestComposer.compose(date: makeDate(), signals: [signal])
        XCTAssertTrue(text.contains("\"Dinner with the team\" in the afternoon at Luigi's Trattoria"))
    }

    func testCalendarClauseNeverLeaksAttendeeNames() {
        let signal = DaySignal(kind: .calendar, timestamp: makeDate())
        signal.setPayload(CalendarPayload(eventIdentifier: "1", title: "Standup", attendeeNames: ["Alex Priv"]))

        let text = DigestComposer.compose(date: makeDate(), signals: [signal])
        XCTAssertFalse(text.contains("Alex Priv"))
    }

    func testPhotosClauseIncludesPlaceAndTimeOfDay() {
        let signal = DaySignal(kind: .photo, timestamp: makeDate())
        signal.setPayload(PhotoPayload(
            assetLocalIdentifier: "abc",
            isScreenshot: false,
            placeName: "Golden Gate Park",
            latitude: 37.77,
            longitude: -122.47
        ))

        let text = DigestComposer.compose(date: makeDate(), signals: [signal])
        XCTAssertTrue(text.contains("Took one photo around Golden Gate Park in the afternoon"))
    }

    func testWeatherClauseIncludesTemperatures() {
        let signal = DaySignal(kind: .weather, timestamp: makeDate())
        signal.setPayload(WeatherPayload(conditionDescription: "Rain", highTemperatureCelsius: 17.6, lowTemperatureCelsius: 9.3))

        let text = DigestComposer.compose(date: makeDate(), signals: [signal])
        XCTAssertTrue(text.contains("Rain, high around 18°, low around 9°"))
    }

    func testComposeUsesTheDaysOwnTimeZoneForTimeOfDay() {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 4
        components.hour = 21
        let ninePMUTC = utcCalendar.date(from: components)!

        let signal = DaySignal(kind: .calendar, timestamp: ninePMUTC)
        signal.setPayload(CalendarPayload(eventIdentifier: "1", title: "Breakfast", attendeeNames: []))

        // 21:00 UTC is 06:00 the next morning in Tokyo — the day's stored
        // zone must win over whatever zone the test machine is in.
        let text = DigestComposer.compose(
            date: ninePMUTC,
            signals: [signal],
            timeZoneIdentifier: "Asia/Tokyo"
        )
        XCTAssertTrue(text.contains("\"Breakfast\" in the morning"))
        XCTAssertTrue(text.contains("March 5"))
    }

    func testRefinementQuestionsUseEventLocationAndPhotoPlace() {
        let event = DaySignal(kind: .calendar, timestamp: makeDate())
        event.setPayload(CalendarPayload(eventIdentifier: "1", title: "Standup", attendeeNames: [], location: "Room B"))

        let photo = DaySignal(kind: .photo, timestamp: makeDate())
        photo.setPayload(PhotoPayload(assetLocalIdentifier: "abc", isScreenshot: false, placeName: "Golden Gate Park"))

        let questions = DigestComposer.refinementQuestions(signals: [event, photo])
        XCTAssertTrue(questions.contains("How did \"Standup\" at Room B go, and who was there?"))
        XCTAssertTrue(questions.contains("You took photos around Golden Gate Park — what was happening there?"))
    }

    func testRefinementQuestionsAskAboutSpecificSignals() {
        let questions = DigestComposer.refinementQuestions(signals: makeMixedSignals())

        XCTAssertTrue(questions.contains { $0.contains("Flatiron") })
        XCTAssertTrue(questions.contains { $0.contains("Standup") })
        XCTAssertTrue(questions.contains { $0.contains("photo") })
        XCTAssertTrue(questions.contains("How were you feeling that day?"))
        XCTAssertLessThanOrEqual(questions.count, 5)
    }

    func testRefinementQuestionsWithNoSignalsStillAskTheOpenOnes() {
        let questions = DigestComposer.refinementQuestions(signals: [])

        XCTAssertEqual(questions, [
            "How were you feeling that day?",
            "Anything else worth remembering?",
        ])
    }

    @MainActor func testGuidedComposeWithBaseTextLeadsWithTheDigest() {
        let composed = GuidedEntryView.compose(
            baseText: "Wednesday, March 4. Spent time at Flatiron.",
            answers: ["It was a work trip.", "", "Felt good."]
        )

        XCTAssertEqual(
            composed,
            "Wednesday, March 4. Spent time at Flatiron.\n\nIt was a work trip.\n\nFelt good."
        )
    }

    func testGuidedComposeWithEmptyBaseTextMatchesPlainCompose() {
        let answers = ["One thing.", "Another."]
        XCTAssertEqual(
            GuidedEntryView.compose(baseText: "", answers: answers),
            GuidedEntryView.compose(answers: answers)
        )
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
