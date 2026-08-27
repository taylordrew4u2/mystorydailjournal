import Foundation

/// Rule-based digest composition (§9). Deterministic, offline, no model
/// calls — running this twice against the same signals must produce
/// byte-identical text, since `DigestEngine` relies on that for idempotent
/// regeneration.
///
/// Template assembly order: places visited, calendar events, photos taken,
/// activity, weather.
enum DigestComposer {
    static func compose(date: Date, signals: [DaySignal], timeZoneIdentifier: String = TimeZone.current.identifier) -> String {
        // All "when during the day" language is anchored to the timezone the
        // day occurred in (the record's stored zone, §10) — reading a Tokyo
        // day back home must not shift its mornings into afternoons.
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current

        var clauses: [String] = [dateHeadline(for: date, timeZone: calendar.timeZone)]

        if let visitClause = visitsClause(signals) {
            clauses.append(visitClause)
        }
        if let calendarClause = calendarClause(signals, calendar: calendar) {
            clauses.append(calendarClause)
        }
        if let photoClause = photosClause(signals, calendar: calendar) {
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
        if let sharedClause = sharedItemsClause(signals) {
            clauses.append(sharedClause)
        }
        if let attachmentsClause = attachmentsClause(signals) {
            clauses.append(attachmentsClause)
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
        for visit in visits.prefix(2) {
            // A bare street address (digits in the name) means the geocoder
            // didn't know the venue — ask what the place actually is.
            if visit.placeName.contains(where: \.isNumber) {
                questions.append("What's at \(visit.placeName)?")
            } else {
                questions.append("You spent time at \(visit.placeName) — what were you doing there?")
            }
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

    private static func dateHeadline(for date: Date, timeZone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day()
        style.timeZone = timeZone
        return date.formatted(style) + "."
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
    private static func calendarClause(_ signals: [DaySignal], calendar: Calendar) -> String? {
        let events = signals
            .filter { $0.kind == .calendar }
            .sorted { $0.timestamp < $1.timestamp }

        let described: [String] = events.compactMap { signal in
            guard let payload = signal.payload(as: CalendarPayload.self) else { return nil }
            var description = "\"\(payload.title)\" \(timeOfDayPhrase(for: signal.timestamp, calendar: calendar))"
            if let location = payload.location {
                description += " at \(location)"
            }
            return description
        }

        guard !described.isEmpty else { return nil }
        return "On the calendar: " + described.joined(separator: "; ") + "."
    }

    private static func photosClause(_ signals: [DaySignal], calendar: Calendar) -> String? {
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
                sentence += " \(timeOfDayPhrase(for: median, calendar: calendar))"
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

    /// Content the user pushed in from other apps (Share Extension or the
    /// M8 ingestion intent). The text is the user's own selection, so it
    /// belongs in the story verbatim (trimmed to a snippet).
    private static func sharedItemsClause(_ signals: [DaySignal]) -> String? {
        let items = signals
            .filter { $0.kind == .sharedItem }
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { $0.payload(as: SharedItemPayload.self) }
        guard !items.isEmpty else { return nil }

        let described = items.map { item in
            let snippet = item.text.count > 120
                ? String(item.text.prefix(120)) + "…"
                : item.text
            if let title = item.title, !title.isEmpty {
                return "Saved \"\(title)\": \(snippet)"
            }
            return "Saved a note: \"\(snippet)\""
        }
        return described.joined(separator: " ") + (described.last?.hasSuffix(".") == true ? "" : ".")
    }

    /// Things the user pinned to the day by hand from the entry view. Notes
    /// go in verbatim — they're the most direct detail the user can give —
    /// while photos and files contribute what's known about them.
    private static func attachmentsClause(_ signals: [DaySignal]) -> String? {
        let attachments = signals
            .filter { $0.kind == .attachment }
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { $0.payload(as: AttachmentPayload.self) }
        guard !attachments.isEmpty else { return nil }

        var parts: [String] = []
        for note in attachments.filter({ $0.kind == .note }).compactMap(\.text) {
            parts.append("From my own notes: \"\(note)\"")
        }
        let photoCount = attachments.filter { $0.kind == .photo }.count
        if photoCount > 0 {
            parts.append(photoCount == 1
                ? "Pinned a photo to this day"
                : "Pinned \(photoCount) photos to this day")
        }
        let fileNames = attachments.filter { $0.kind == .file }.compactMap(\.fileName)
        if !fileNames.isEmpty {
            parts.append("Attached \(fileNames.joined(separator: ", "))")
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ". ") + "."
    }

    /// Deterministic bucket for "when during the day," shared by every
    /// clause that has a meaningful timestamp to lean on. The calendar
    /// carries the day's own timezone, not necessarily the device's.
    private static func timeOfDayPhrase(for date: Date, calendar: Calendar) -> String {
        switch calendar.component(.hour, from: date) {
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
