import Foundation

/// Rule-based digest composition (§9). Deterministic, offline, no model
/// calls — running this twice against the same signals must produce
/// byte-identical text, since `DigestEngine` relies on that for idempotent
/// regeneration.
///
/// Template assembly order: places visited, calendar events, photos taken,
/// activity, weather.
enum DigestComposer {
    static func compose(date: Date, signals: [DaySignal]) -> String {
        var clauses: [String] = [dateHeadline(for: date)]

        if let visitClause = visitsClause(signals) {
            clauses.append(visitClause)
        }
        if let calendarClause = calendarClause(signals) {
            clauses.append(calendarClause)
        }
        if let photoClause = photosClause(signals) {
            clauses.append(photoClause)
        }
        if let activityClause = activityClause(signals) {
            clauses.append(activityClause)
        }
        if let mediaClause = mediaClause(signals) {
            clauses.append(mediaClause)
        }
        if let weatherClause = weatherClause(signals) {
            clauses.append(weatherClause)
        }
        if let fileWatchClause = fileWatchClause(signals) {
            clauses.append(fileWatchClause)
        }

        guard clauses.count > 1 else {
            return "\(clauses[0]) No signals were available for this day."
        }

        return clauses.joined(separator: " ")
    }

    /// Follow-up questions for the guided refinement flow on an
    /// auto-generated day: asks about the concrete things the digest already
    /// knows (places, events, photos, workouts) so the user's answers can
    /// sharpen the entry. Always ends with the two open questions, and stays
    /// within the 3-5 prompt range `QuestionSet` uses everywhere else.
    static func refinementQuestions(signals: [DaySignal]) -> [String] {
        var questions: [String] = []

        let visits = signals
            .filter { $0.kind == .visit }
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { $0.payload(as: VisitPayload.self) }
        if let firstVisit = visits.first {
            questions.append("You spent time at \(firstVisit.placeName) — what were you doing there?")
        }

        let events = signals
            .filter { $0.kind == .calendar }
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { $0.payload(as: CalendarPayload.self) }
        for event in events.prefix(2) {
            if let location = event.location {
                questions.append("How did \"\(event.title)\" at \(location) go, and who was there?")
            } else if !event.attendeeNames.isEmpty {
                questions.append("How did \"\(event.title)\" go, and who was with you?")
            } else {
                questions.append("How did \"\(event.title)\" go?")
            }
        }

        let photos = signals
            .filter { $0.kind == .photo }
            .compactMap { $0.payload(as: PhotoPayload.self) }
        if !photos.isEmpty {
            if let place = photos.compactMap(\.placeName).first {
                questions.append("You took photos around \(place) — what was happening there?")
            } else {
                questions.append(photos.count == 1
                    ? "You took a photo that day — what was it of?"
                    : "You took \(photos.count) photos that day — what were they of?")
            }
        }

        if let activity = signals.first(where: { $0.kind == .activity })?.payload(as: ActivityPayload.self),
           !activity.workoutSummaries.isEmpty {
            questions.append("How did your workout go?")
        }

        // The specific questions above cap at three so these two always fit.
        questions = Array(questions.prefix(3))
        questions.append("How were you feeling that day?")
        questions.append("Anything else worth remembering?")
        return questions
    }

    private static func dateHeadline(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day()) + "."
    }

    private static func visitsClause(_ signals: [DaySignal]) -> String? {
        let visits = signals
            .filter { $0.kind == .visit }
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { $0.payload(as: VisitPayload.self) }

        guard !visits.isEmpty else { return nil }
        let places = visits.map(\.placeName)

        switch places.count {
        case 1:
            return "Spent time at \(places[0])."
        case 2:
            return "Started at \(places[0]), then a stop at \(places[1])."
        default:
            let middle = places.dropFirst().dropLast().joined(separator: ", ")
            return "Started at \(places.first!), spent time in \(middle), then a stop at \(places.last!)."
        }
    }

    /// Names every event with as much of its own metadata as exists: title,
    /// part of the day, and the event's location field. Attendee names ride
    /// in the payload but are deliberately never written here — §4: they
    /// don't enter a digest without the user confirming them (the guided
    /// refinement flow asks instead).
    private static func calendarClause(_ signals: [DaySignal]) -> String? {
        let events = signals
            .filter { $0.kind == .calendar }
            .sorted { $0.timestamp < $1.timestamp }

        let described: [String] = events.compactMap { signal in
            guard let payload = signal.payload(as: CalendarPayload.self) else { return nil }
            var description = "\"\(payload.title)\" \(timeOfDayPhrase(for: signal.timestamp))"
            if let location = payload.location {
                description += " at \(location)"
            }
            return description
        }

        guard !described.isEmpty else { return nil }
        return "On the calendar: " + described.joined(separator: "; ") + "."
    }

    private static func photosClause(_ signals: [DaySignal]) -> String? {
        let photoSignals = signals.filter { $0.kind == .photo }
        let photos = photoSignals.compactMap { $0.payload(as: PhotoPayload.self) }
        guard !photos.isEmpty else { return nil }

        let screenshotCount = photos.filter(\.isScreenshot).count
        let regularCount = photos.count - screenshotCount

        var parts: [String] = []
        if regularCount > 0 {
            parts.append(regularCount == 1 ? "Took one photo" : "Took \(regularCount) photos")
        }
        if screenshotCount > 0 {
            parts.append(screenshotCount == 1 ? "one screenshot" : "\(screenshotCount) screenshots")
        }
        guard !parts.isEmpty else { return nil }
        var sentence = parts.joined(separator: " and ")

        // The asset's own metadata: where the shots were geotagged, and
        // which part of the day the camera was actually out.
        if let place = photos.compactMap(\.placeName).first {
            sentence += " around \(place)"
        }
        if regularCount > 0 {
            let cameraTimes = photoSignals
                .filter { ($0.payload(as: PhotoPayload.self)?.isScreenshot ?? false) == false }
                .map(\.timestamp)
                .sorted()
            if let median = cameraTimes.dropFirst(cameraTimes.count / 2).first {
                sentence += " \(timeOfDayPhrase(for: median))"
            }
        }
        return sentence + "."
    }

    private static func activityClause(_ signals: [DaySignal]) -> String? {
        guard let activity = signals.first(where: { $0.kind == .activity })?.payload(as: ActivityPayload.self) else {
            return nil
        }

        var parts: [String] = []
        if activity.stepCount > 0 {
            parts.append("\(activity.stepCount.formatted()) steps")
        }
        if activity.distanceMeters > 0 {
            let km = activity.distanceMeters / 1000
            parts.append("traveled about \(String(format: "%.1f", km)) km")
        }
        parts.append(contentsOf: activity.workoutSummaries)
        if activity.sleepHours > 0 {
            parts.append("slept about \(String(format: "%.1f", activity.sleepHours)) hours")
        }

        guard !parts.isEmpty else { return nil }
        let sentence = parts.joined(separator: ", ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst() + "."
    }

    private static func mediaClause(_ signals: [DaySignal]) -> String? {
        guard let media = signals.first(where: { $0.kind == .media })?.payload(as: MediaPayload.self),
              !media.titles.isEmpty else {
            return nil
        }
        return media.titles.count == 1
            ? "Listened to \"\(media.titles[0])\"."
            : "Listened to \(media.titles.count) songs, including \"\(media.titles[0])\"."
    }

    private static func weatherClause(_ signals: [DaySignal]) -> String? {
        guard let weather = signals.first(where: { $0.kind == .weather })?.payload(as: WeatherPayload.self) else {
            return nil
        }
        var sentence = weather.conditionDescription
        if let high = weather.highTemperatureCelsius {
            sentence += ", high around \(Int(high.rounded()))°"
        }
        if let low = weather.lowTemperatureCelsius {
            sentence += ", low around \(Int(low.rounded()))°"
        }
        return sentence + "."
    }

    /// Deterministic bucket for "when during the day," shared by every
    /// clause that has a meaningful timestamp to lean on.
    private static func timeOfDayPhrase(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "in the morning"
        case 12..<17: "in the afternoon"
        case 17..<22: "in the evening"
        default: "late at night"
        }
    }

    /// §14: "Granting a watched folder surfaces new files from that folder
    /// in the next digest."
    private static func fileWatchClause(_ signals: [DaySignal]) -> String? {
        let files = signals
            .filter { $0.kind == .fileWatch }
            .compactMap { $0.payload(as: FileWatchPayload.self) }
        guard !files.isEmpty else { return nil }

        return files.count == 1
            ? "One new file in \(files[0].folderName)."
            : "\(files.count) new files in \(files[0].folderName)."
    }
}
