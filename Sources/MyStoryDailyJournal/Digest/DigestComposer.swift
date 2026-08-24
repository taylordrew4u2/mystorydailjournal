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

    private static func calendarClause(_ signals: [DaySignal]) -> String? {
        let events = signals.filter { $0.kind == .calendar }
        guard !events.isEmpty else { return nil }
        return events.count == 1 ? "One calendar event." : "\(events.count) calendar events."
    }

    private static func photosClause(_ signals: [DaySignal]) -> String? {
        let photos = signals
            .filter { $0.kind == .photo }
            .compactMap { $0.payload(as: PhotoPayload.self) }
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
        return parts.joined(separator: " and ") + "."
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
        return weather.conditionDescription + "."
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
