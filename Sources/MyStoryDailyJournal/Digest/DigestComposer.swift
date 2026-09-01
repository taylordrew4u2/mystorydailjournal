import Foundation

/// Rule-based digest composition (§9). Deterministic, offline, no model
/// calls — running this twice against the same signals must produce
/// byte-identical text, since `DigestEngine` relies on that for idempotent
/// regeneration.
///
/// Template assembly order: places visited, calendar events, photos taken,
/// activity, weather.
enum DigestComposer {
    /// `placeAliases` carries the venue names the writer has confirmed for
    /// bare addresses (`PlaceAliasStore`), so a day composed today writes
    /// "Blue Bottle" where the geocoder only knew "480 Larkin Street" —
    /// including on days recorded long before the writer said so. Passed in
    /// as a plain dictionary to keep composition a pure function of its
    /// inputs.
    static func compose(
        date: Date,
        signals: [DaySignal],
        timeZoneIdentifier: String = TimeZone.current.identifier,
        placeAliases: [String: String] = PlaceAliasStore.aliases()
    ) -> String {
        // All "when during the day" language is anchored to the timezone the
        // day occurred in (the record's stored zone, §10) — reading a Tokyo
        // day back home must not shift its mornings into afternoons.
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current

        var clauses: [String] = [dateHeadline(for: date, timeZone: calendar.timeZone)]

        if let visitClause = visitsClause(signals, placeAliases: placeAliases) {
            clauses.append(visitClause)
        }
        if let calendarClause = calendarClause(signals, calendar: calendar) {
            clauses.append(calendarClause)
        }
        if let photoClause = photosClause(signals, calendar: calendar, placeAliases: placeAliases) {
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
        if let socialClause = socialPostsClause(signals) {
            clauses.append(socialClause)
        }

        guard clauses.count > 1 else {
            return "\(clauses[0]) I don't have much to go on for this day yet."
        }

        return clauses.joined(separator: " ")
    }

    /// Follow-up questions for the guided refinement flow on an
    /// auto-generated day. The list itself is built by
    /// `GuidedQuestionBuilder`, which knows about photos and faces as well
    /// as places and events; this stays as the text-only view of it for
    /// callers that just want the prompts.
    static func refinementQuestions(signals: [DaySignal]) -> [String] {
        GuidedQuestionBuilder.questions(signals: signals).map(\.text)
    }

    private static func dateHeadline(for date: Date, timeZone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day()
        style.timeZone = timeZone
        return date.formatted(style) + "."
    }

    /// Where the day was spent. Places the writer said they were only
    /// walking past are left out entirely — a day is not a list of every
    /// corner the phone noticed — and a place whose name doesn't say what
    /// it is gets what Maps (or the writer) called it.
    private static func visitsClause(_ signals: [DaySignal], placeAliases: [String: String]) -> String? {
        let visits = signals
            .filter { $0.kind == .visit }
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { $0.payload(as: VisitPayload.self) }
            .filter { !$0.isPassingThrough }

        guard !visits.isEmpty else { return nil }
        // A place the writer has named is written by its name, never by the
        // address the geocoder handed back.
        var places: [(name: String, categoryLabel: String?)] = []
        for visit in visits {
            let name = PlaceAliasStore.resolve(
                rawName: visit.placeName,
                latitude: visit.latitude,
                longitude: visit.longitude,
                in: placeAliases
            ) ?? visit.placeName
            if places.last?.name != name { places.append((name, visit.categoryLabel)) }
        }

        let names = places.map(\.name)
        switch places.count {
        case 1:
            let place = places[0]
            if let label = describableCategory(of: place.name, categoryLabel: place.categoryLabel) {
                return "I spent time at \(place.name), the \(label)."
            }
            return "I spent time at \(place.name)."
        case 2:
            return "I started at \(names[0]), then stopped at \(names[1])."
        default:
            let middle = names.dropFirst().dropLast().joined(separator: ", ")
            return "I started at \(names.first!), spent time in \(middle), then stopped at \(names.last!)."
        }
    }

    /// A category is worth writing only when the name doesn't already say
    /// it: "Cobb's, the comedy club" earns its words; "the comedy club, the
    /// comedy club" does not.
    private static func describableCategory(of name: String, categoryLabel: String?) -> String? {
        guard let categoryLabel = categoryLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !categoryLabel.isEmpty else { return nil }
        let loweredName = name.lowercased()
        let alreadySaid = categoryLabel
            .split(separator: " ")
            .allSatisfy { loweredName.contains($0.lowercased()) }
        return alreadySaid ? nil : categoryLabel
    }

    /// Names every event with as much of its own metadata as exists: title,
    /// part of the day, and the event's location field. Guest lists are not
    /// used; people enter the diary only when the writer names or tags them.
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
        return "I had " + described.joined(separator: "; ") + " on the calendar."
    }

    /// Everything the day's photos can say for themselves: how many were
    /// taken, where they were geotagged, when the camera was out, what
    /// Vision thought they were of, and who was in them — by name when the
    /// writer has confirmed one, and by description ("two people in the
    /// frame") when they haven't (§4).
    private static func photosClause(
        _ signals: [DaySignal],
        calendar: Calendar,
        placeAliases: [String: String]
    ) -> String? {
        let photoSignals = signals.filter { $0.kind == .photo }
        let photos = photoSignals.compactMap { $0.payload(as: PhotoPayload.self) }
        guard !photos.isEmpty else { return nil }

        let screenshotCount = photos.filter(\.isScreenshot).count
        let regularCount = photos.count - screenshotCount

        var parts: [String] = []
        if regularCount > 0 {
            parts.append(regularCount == 1 ? "took one photo" : "took \(regularCount) photos")
        }
        if screenshotCount > 0 {
            parts.append(screenshotCount == 1 ? "saved one screenshot" : "saved \(screenshotCount) screenshots")
        }
        guard !parts.isEmpty else { return nil }
        var sentence = "I " + parts.joined(separator: " and ")

        // The asset's own metadata: where the shots were geotagged, and
        // which part of the day the camera was actually out.
        if let placeName = photos.compactMap(\.placeName).first {
            let resolved = photos.first { $0.placeName == placeName }.flatMap { photo in
                PlaceAliasStore.resolve(
                    rawName: placeName,
                    latitude: photo.latitude,
                    longitude: photo.longitude,
                    in: placeAliases
                )
            }
            sentence += " around \(resolved ?? placeName)"
        }
        if regularCount > 0 {
            let cameraTimes = photoSignals
                .filter { ($0.payload(as: PhotoPayload.self)?.isScreenshot ?? false) == false }
                .map(\.timestamp)
                .sorted()
            if let phrase = cameraTimePhrase(cameraTimes, calendar: calendar) {
                sentence += " \(phrase)"
            }
        }

        let cameraPhotos = photos.filter { !$0.isScreenshot }
        if let scenes = sceneSummary(of: cameraPhotos) {
            sentence += ", mostly of \(scenes)"
        }
        if let people = peopleSummary(of: cameraPhotos) {
            sentence += ", \(people)"
        }
        if cameraPhotos.contains(where: \.isFavorite) {
            sentence += ", one of them a favorite"
        }
        return sentence + "."
    }

    /// One bucket when the camera came out once, a span when the day's
    /// shots stretch across the day.
    private static func cameraTimePhrase(_ times: [Date], calendar: Calendar) -> String? {
        guard let first = times.first, let last = times.last else { return nil }
        let start = timeOfDayNoun(for: first, calendar: calendar)
        let end = timeOfDayNoun(for: last, calendar: calendar)
        if start == end {
            return timeOfDayPhrase(for: first, calendar: calendar)
        }
        return "from the \(start) into the \(end)"
    }

    /// The one or two things Vision saw most often across the day's shots.
    /// Ordered by how many photos carried the label, then alphabetically,
    /// so the same signals always compose the same sentence.
    private static func sceneSummary(of photos: [PhotoPayload]) -> String? {
        let counts = photos
            .flatMap(\.sceneLabels)
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        guard !counts.isEmpty else { return nil }

        let ranked = counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(2)
            .map(\.key)
        return list(ranked)
    }

    /// Names only when the writer confirmed them; otherwise a count of the
    /// faces the phone saw, which describes the moment without claiming to
    /// know anyone.
    private static func peopleSummary(of photos: [PhotoPayload]) -> String? {
        let names = photos.flatMap(\.personNames)
        if !names.isEmpty {
            var unique: [String] = []
            for name in names where !unique.contains(name) { unique.append(name) }
            return "with \(list(unique)) in the frame"
        }

        guard let faces = photos.map(\.faceCount).max(), faces > 0 else { return nil }
        return faces == 1
            ? "with one person in the frame"
            : "with \(spelled(faces)) people in the frame"
    }

    private static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: items.dropLast().joined(separator: ", ") + ", and \(items.last!)"
        }
    }

    private static func spelled(_ count: Int) -> String {
        switch count {
        case 2: "two"
        case 3: "three"
        case 4: "four"
        case 5: "five"
        case 6: "six"
        default: "\(count)"
        }
    }

    private static func activityClause(_ signals: [DaySignal]) -> String? {
        guard let activity = signals.first(where: { $0.kind == .activity })?.payload(as: ActivityPayload.self) else {
            return nil
        }

        var parts: [String] = []
        if let movement = movementPhrase(forStepCount: activity.stepCount, distanceMeters: activity.distanceMeters) {
            parts.append(movement)
        }
        if activity.distanceMeters > 0 {
            let km = activity.distanceMeters / 1000
            if activity.stepCount <= 0 {
                parts.append("covered about \(String(format: "%.1f", km)) km")
            }
        }
        parts.append(contentsOf: activity.workoutSummaries)
        if activity.sleepHours > 0 {
            parts.append("slept about \(String(format: "%.1f", activity.sleepHours)) hours")
        }

        guard !parts.isEmpty else { return nil }
        let sentence = parts.joined(separator: ", ")
        return "I " + sentence + "."
    }

    private static func movementPhrase(forStepCount stepCount: Int, distanceMeters: Double) -> String? {
        guard stepCount > 0 else { return nil }

        switch stepCount {
        case 0..<4_000:
            return nil
        case 4_000..<9_000:
            return "got some movement in"
        case 9_000..<18_000:
            return "spent a lot of the day on foot"
        default:
            if distanceMeters >= 12_000 {
                return "had an unusually long day on foot"
            }
            return "had an unusually active day"
        }
    }

    private static func mediaClause(_ signals: [DaySignal]) -> String? {
        guard let media = signals.first(where: { $0.kind == .media })?.payload(as: MediaPayload.self),
              !media.titles.isEmpty else {
            return nil
        }
        return media.titles.count == 1
            ? "I listened to \"\(media.titles[0])\"."
            : "I listened to \(media.titles.count) songs, including \"\(media.titles[0])\"."
    }

    private static func weatherClause(_ signals: [DaySignal]) -> String? {
        guard let weather = signals.first(where: { $0.kind == .weather })?.payload(as: WeatherPayload.self) else {
            return nil
        }
        var sentence = "The weather was \(weather.conditionDescription)"
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
                return "I saved \"\(title)\": \(snippet)"
            }
            return "I saved a note: \"\(snippet)\""
        }
        return described.joined(separator: " ") + (described.last?.hasSuffix(".") == true ? "" : ".")
    }

    /// What the writer posted publicly that day, out of a social archive
    /// they imported. The caption is their own words, so it goes in the way
    /// a shared note does; the picture count is context, not a gallery.
    private static func socialPostsClause(_ signals: [DaySignal]) -> String? {
        let posts = signals
            .filter { $0.kind == .socialPost }
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { $0.payload(as: SocialPostPayload.self) }
        guard !posts.isEmpty else { return nil }

        var parts: [String] = []
        for post in posts.prefix(4) {
            let snippet = post.text.count > 140
                ? String(post.text.prefix(140)) + "…"
                : post.text
            if snippet.isEmpty {
                parts.append(post.mediaCount == 1
                    ? "I put a photo on \(post.network)"
                    : "I put \(post.mediaCount) photos on \(post.network)")
            } else {
                parts.append("I posted on \(post.network): \"\(snippet)\"")
            }
        }
        if posts.count > parts.count {
            let rest = posts.count - parts.count
            parts.append(rest == 1 ? "and one more post" : "and \(rest) more posts")
        }
        return parts.joined(separator: ". ") + "."
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
            parts.append("I noted: \"\(note)\"")
        }
        let photoCount = attachments.filter { $0.kind == .photo }.count
        if photoCount > 0 {
            parts.append(photoCount == 1
                ? "I pinned a photo to this day"
                : "I pinned \(photoCount) photos to this day")
        }
        let fileNames = attachments.filter { $0.kind == .file }.compactMap(\.fileName)
        if !fileNames.isEmpty {
            parts.append("I attached \(fileNames.joined(separator: ", "))")
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

    /// The same buckets as a bare noun, for spans ("from the morning into
    /// the evening").
    private static func timeOfDayNoun(for date: Date, calendar: Calendar) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: "morning"
        case 12..<17: "afternoon"
        case 17..<22: "evening"
        default: "night"
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
            ? "One new file showed up in \(files[0].folderName)."
            : "\(files.count) new files showed up in \(files[0].folderName)."
    }
}
