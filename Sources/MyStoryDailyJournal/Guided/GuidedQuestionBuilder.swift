import Foundation

/// Builds the guided questions for one day out of what the phone already
/// noticed. Every question is about something concrete — a place, an
/// event, a photo, the faces in it — so that answering makes the entry
/// more specific rather than more generic.
///
/// Two rules shape the list:
/// - **Every unnamed place gets asked about.** An address in a diary entry
///   is a failure; the answer renames it everywhere (`PlaceRenamer`).
/// - **Photos come with the question.** The asset identifiers ride along so
///   the writer sees the shot from that day while answering it.
enum GuidedQuestionBuilder {
    struct ContextSummary: Equatable {
        let parts: [String]

        var isActive: Bool { !parts.isEmpty }

        var shortDescription: String {
            guard !parts.isEmpty else { return "open prompts" }
            return ListFormatter.localizedString(byJoining: parts)
        }
    }

    /// How many signal-specific questions to ask before the two open ones.
    /// Address questions are exempt — being asked where you were is the
    /// point, and there are rarely many in a day.
    private static let specificQuestionLimit = 10

    /// Photos taken within this much of a place or event are shown with
    /// its question — close enough to be the same moment.
    private static let photoProximity: TimeInterval = 90 * 60

    static func questions(
        signals: [DaySignal],
        timeZoneIdentifier: String = TimeZone.current.identifier,
        aliases: [String: String] = PlaceAliasStore.aliases()
    ) -> [GuidedQuestion] {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current

        let photos = signals
            .filter { $0.kind == .photo }
            .compactMap { signal -> (signal: DaySignal, payload: PhotoPayload)? in
                guard let payload = signal.payload(as: PhotoPayload.self) else { return nil }
                return (signal, payload)
            }
            .sorted { $0.signal.timestamp < $1.signal.timestamp }

        var addressQuestions: [GuidedQuestion] = []
        var otherQuestions: [GuidedQuestion] = []

        for question in placeQuestions(signals: signals, photos: photos, aliases: aliases) {
            if question.renamablePlace != nil {
                addressQuestions.append(question)
            } else {
                otherQuestions.append(question)
            }
        }

        otherQuestions += eventQuestions(signals: signals, photos: photos)
        otherQuestions += savedItemQuestions(signals: signals)
        otherQuestions += socialPostQuestions(signals: signals)
        if let photoQuestion = photoQuestion(photos: photos) {
            otherQuestions.append(photoQuestion)
        }
        if let peopleQuestion = peopleInPhotoQuestion(photos: photos, calendar: calendar) {
            otherQuestions.append(peopleQuestion)
        }
        if let activityQuestion = activityQuestion(signals: signals) {
            otherQuestions.append(activityQuestion)
        }
        if let mediaQuestion = mediaQuestion(signals: signals) {
            otherQuestions.append(mediaQuestion)
        }
        if let weatherQuestion = weatherQuestion(signals: signals) {
            otherQuestions.append(weatherQuestion)
        }

        let specific = addressQuestions + otherQuestions.prefix(max(0, specificQuestionLimit - addressQuestions.count))
        return specific + openQuestions
    }

    static func contextSummary(for signals: [DaySignal]) -> ContextSummary {
        var parts: [String] = []

        if signals.contains(where: { $0.kind == .photo }) {
            parts.append("photos")
        }
        if signals.contains(where: { $0.kind == .visit }) {
            parts.append("places")
        }
        if signals.contains(where: { $0.kind == .calendar }) {
            parts.append("calendar")
        }
        if signals.contains(where: { $0.kind == .activity }) {
            parts.append("movement")
        }
        if signals.contains(where: { $0.kind == .media }) {
            parts.append("music")
        }
        if signals.contains(where: { $0.kind == .sharedItem || $0.kind == .attachment || $0.kind == .fileWatch }) {
            parts.append("notes")
        }
        if signals.contains(where: { $0.kind == .socialPost }) {
            parts.append("your posts")
        }

        return ContextSummary(parts: parts)
    }

    static func continuationQuestion(after responses: [GuidedResponse], signals: [DaySignal]) -> GuidedQuestion {
        let promptCount = responses.count
        let templates = continuationTemplates(hasMovement: signals.contains { $0.kind == .activity })
        let templateIndex = promptCount % templates.count
        let cycle = promptCount / templates.count
        let template = templates[templateIndex]
        return GuidedQuestion(
            id: "open.continue.\(promptCount)",
            text: continuationText(template.text, cycle: cycle),
            subject: .open,
            feelingPrompt: template.feelingPrompt
        )
    }

    /// The two questions every day ends on, whatever else it had.
    private static var openQuestions: [GuidedQuestion] {
        [
            GuidedQuestion(id: "open.feeling", text: "How were you feeling that day?", feelingPrompt: nil),
            GuidedQuestion(
                id: "open.anythingElse",
                text: "Anything else worth remembering?",
                feelingPrompt: "How do you feel about the day now, looking back?"
            ),
        ]
    }

    private static func continuationTemplates(hasMovement: Bool) -> [(text: String, feelingPrompt: String?)] {
        var templates: [(text: String, feelingPrompt: String?)] = [
            ("What part of the day still feels unfinished?", "How does that part feel now?"),
            ("What would you want to remember about this day later?", "How do you feel about that now?"),
            ("What kept pulling your attention today?", "How did that attention feel?"),
            ("Was there a small moment I should include?", "How do you feel about that moment now?"),
            ("What changed between the start of the day and the end?", "How did that change feel?"),
            ("What did you not get to say about this day yet?", "How does it feel saying it now?"),
        ]
        if hasMovement {
            templates.insert(
                ("Was there a moment that explains why the day had so much movement?", "How did your body feel in that part of the day?"),
                at: 2
            )
            templates.insert(
                ("Did moving around change your mood, or was it just the shape of the day?", "How did it feel by the end?"),
                at: 5
            )
        }
        return templates
    }

    private static func continuationText(_ text: String, cycle: Int) -> String {
        guard cycle > 0 else { return text }
        let lenses = [
            "Think about the morning.",
            "Think about the middle of the day.",
            "Think about the evening.",
            "Think about what changed your mood.",
            "Think about what you might forget first.",
            "Think about what felt private or hard to explain.",
        ]
        return "\(text) \(lenses[(cycle - 1) % lenses.count])"
    }

    /// Visits first, then any place a photo was geotagged to that no visit
    /// already covered — an address is an address wherever it came from.
    private static func placeQuestions(
        signals: [DaySignal],
        photos: [(signal: DaySignal, payload: PhotoPayload)],
        aliases: [String: String]
    ) -> [GuidedQuestion] {
        var questions: [GuidedQuestion] = []
        var askedPlaces = Set<String>()
        var namedPlaceCount = 0

        // A stop the writer already dismissed as walking past is never
        // asked about again.
        let visits = signals
            .filter { $0.kind == .visit }
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { signal -> (signal: DaySignal, payload: VisitPayload)? in
                guard let payload = signal.payload(as: VisitPayload.self), !payload.isPassingThrough else { return nil }
                return (signal, payload)
            }

        for visit in visits {
            let resolved = PlaceAliasStore.resolve(
                rawName: visit.payload.placeName,
                latitude: visit.payload.latitude,
                longitude: visit.payload.longitude,
                in: aliases
            ) ?? visit.payload.placeName
            guard askedPlaces.insert(resolved.lowercased()).inserted else { continue }

            let nearbyPhotos = assetIdentifiers(from: photos, near: visit.signal.timestamp)
            if PlaceNameResolver.looksLikeAddress(resolved) {
                questions.append(GuidedQuestion(
                    id: "place.\(resolved)",
                    text: "What's at \(resolved)?",
                    subject: .place(rawName: resolved, latitude: visit.payload.latitude, longitude: visit.payload.longitude),
                    photoAssetIdentifiers: nearbyPhotos,
                    feelingPrompt: "How did being there feel?"
                ))
            } else if namedPlaceCount < 2 {
                namedPlaceCount += 1
                questions.append(GuidedQuestion(
                    id: "place.\(resolved)",
                    text: "You spent time at \(resolved) — what were you doing there?",
                    subject: .place(rawName: resolved, latitude: visit.payload.latitude, longitude: visit.payload.longitude),
                    photoAssetIdentifiers: nearbyPhotos,
                    feelingPrompt: "How did being there feel?"
                ))
            }
        }

        for photo in photos {
            guard let placeName = photo.payload.placeName else { continue }
            let resolved = PlaceAliasStore.resolve(
                rawName: placeName,
                latitude: photo.payload.latitude,
                longitude: photo.payload.longitude,
                in: aliases
            ) ?? placeName
            guard PlaceNameResolver.looksLikeAddress(resolved) else { continue }
            guard askedPlaces.insert(resolved.lowercased()).inserted else { continue }

            questions.append(GuidedQuestion(
                id: "place.\(resolved)",
                text: "What's at \(resolved)?",
                subject: .place(rawName: resolved, latitude: photo.payload.latitude, longitude: photo.payload.longitude),
                photoAssetIdentifiers: assetIdentifiers(from: photos, near: photo.signal.timestamp),
                feelingPrompt: "How did being there feel?"
            ))
        }

        return questions
    }

    private static func eventQuestions(
        signals: [DaySignal],
        photos: [(signal: DaySignal, payload: PhotoPayload)]
    ) -> [GuidedQuestion] {
        signals
            .filter { $0.kind == .calendar }
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { signal -> GuidedQuestion? in
                guard let payload = signal.payload(as: CalendarPayload.self) else { return nil }
                let text = eventQuestionText(for: payload)
                return GuidedQuestion(
                    id: "event.\(payload.eventIdentifier)",
                    text: text,
                    subject: .event(title: payload.title),
                    photoAssetIdentifiers: assetIdentifiers(from: photos, near: signal.timestamp),
                    feelingPrompt: "How did it leave you feeling?"
                )
            }
            .prefix(2)
            .map { $0 }
    }

    private static func eventQuestionText(for payload: CalendarPayload) -> String {
        if let location = payload.location {
            return "How did \"\(payload.title)\" at \(location) shape the day?"
        }
        return "How did \"\(payload.title)\" shape the day?"
    }

    private static func savedItemQuestions(signals: [DaySignal]) -> [GuidedQuestion] {
        let sharedItems = signals
            .filter { $0.kind == .sharedItem }
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { $0.payload(as: SharedItemPayload.self) }

        let attachments = signals
            .filter { $0.kind == .attachment }
            .compactMap { $0.payload(as: AttachmentPayload.self) }

        var questions: [GuidedQuestion] = []
        if let item = sharedItems.first {
            let subject = item.title?.nilIfBlank ?? item.sourceApp?.nilIfBlank ?? "something you saved"
            questions.append(GuidedQuestion(
                id: "saved.shared",
                text: "You saved \(subject) today. What made it worth keeping?",
                subject: .open,
                feelingPrompt: "What does it bring up now?"
            ))
        }
        if attachments.contains(where: { $0.kind == .note }) {
            questions.append(GuidedQuestion(
                id: "saved.note",
                text: "You added a note to this day. What is the part behind the note?",
                subject: .open,
                feelingPrompt: "How does that detail feel now?"
            ))
        }
        if attachments.contains(where: { $0.kind == .file }) {
            questions.append(GuidedQuestion(
                id: "saved.file",
                text: "You attached a file here. What should you remember about it?",
                subject: .open,
                feelingPrompt: "How did that work feel today?"
            ))
        }
        return questions
    }

    private static func socialPostQuestions(signals: [DaySignal]) -> [GuidedQuestion] {
        signals
            .filter { $0.kind == .socialPost }
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { $0.payload(as: SocialPostPayload.self) }
            .prefix(2)
            .map { post in
                GuidedQuestion(
                    id: "social.\(post.externalID)",
                    text: "You posted on \(post.network) today. What was the private side of that moment?",
                    subject: .open,
                    feelingPrompt: "How did it feel after sharing it?"
                )
            }
    }

    private static func activityQuestion(signals: [DaySignal]) -> GuidedQuestion? {
        guard let activity = signals.first(where: { $0.kind == .activity })?.payload(as: ActivityPayload.self) else {
            return nil
        }
        if !activity.workoutSummaries.isEmpty {
            return GuidedQuestion(
                id: "activity.workout",
                text: "How did your workout go?",
                subject: .activity,
                feelingPrompt: "How did your body feel afterwards?"
            )
        }
        guard let movementDescription = movementQuestionDescription(forStepCount: activity.stepCount) else {
            return nil
        }
        return GuidedQuestion(
            id: "activity.movement",
            text: "\(movementDescription). What did that movement say about the day?",
            subject: .activity,
            feelingPrompt: "How did your body feel by the end?"
        )
    }

    private static func movementQuestionDescription(forStepCount stepCount: Int) -> String? {
        switch stepCount {
        case ..<4_000:
            return nil
        case 4_000..<9_000:
            return "You got some movement in today"
        case 9_000..<18_000:
            return "You spent a lot of the day on foot"
        default:
            return "This was an unusually active day"
        }
    }

    private static func mediaQuestion(signals: [DaySignal]) -> GuidedQuestion? {
        let titles = signals
            .filter { $0.kind == .media }
            .compactMap { $0.payload(as: MediaPayload.self) }
            .flatMap(\.titles)
        guard let title = titles.first else { return nil }
        return GuidedQuestion(
            id: "media",
            text: "\"\(title)\" was part of the day. What did it match or change?",
            subject: .open,
            feelingPrompt: "What did it make you feel?"
        )
    }

    private static func weatherQuestion(signals: [DaySignal]) -> GuidedQuestion? {
        guard let weather = signals.first(where: { $0.kind == .weather })?.payload(as: WeatherPayload.self) else {
            return nil
        }
        return GuidedQuestion(
            id: "weather",
            text: "The weather was \(weather.conditionDescription). Did that change the mood of the day?",
            subject: .open,
            feelingPrompt: "How did it feel being in that weather?"
        )
    }

    /// One question about the day's camera roll, with the shots attached so
    /// the writer answers while looking at them.
    private static func photoQuestion(photos: [(signal: DaySignal, payload: PhotoPayload)]) -> GuidedQuestion? {
        let cameraPhotos = photos.filter { !$0.payload.isScreenshot }
        // Screenshots are all there is to show on a day without any real
        // photos, so they stand in rather than the question disappearing.
        let shown = cameraPhotos.isEmpty ? photos : cameraPhotos
        guard !shown.isEmpty else { return nil }

        let identifiers = shown.prefix(4).map(\.payload.assetLocalIdentifier)
        // A place already covered by its own "what's at this address?"
        // question would only repeat the address here.
        if let place = shown.compactMap(\.payload.placeName).first(where: { !PlaceNameResolver.looksLikeAddress($0) }) {
            return GuidedQuestion(
                id: "photos.place",
                text: "You took photos around \(place) — what was happening there?",
                subject: .photos,
                photoAssetIdentifiers: identifiers,
                feelingPrompt: "What do you feel looking at them now?"
            )
        }
        return GuidedQuestion(
            id: "photos.all",
            text: shown.count == 1
                ? "You took a photo that day — what was it of?"
                : "You took \(shown.count) photos that day — what were they of?",
            subject: .photos,
            photoAssetIdentifiers: identifiers,
            feelingPrompt: "What do you feel looking at them now?"
        )
    }

    /// The phone can count faces but never name them (§4). So it describes
    /// what it sees — "two people, 6:12 PM" — and asks who they were, with
    /// the day's known names offered as one-tap answers.
    private static func peopleInPhotoQuestion(
        photos: [(signal: DaySignal, payload: PhotoPayload)],
        calendar: Calendar
    ) -> GuidedQuestion? {
        let candidates = photos.filter {
            !$0.payload.isScreenshot && $0.payload.faceCount > 0 && $0.payload.personNames.isEmpty
        }
        guard let busiest = candidates.max(by: { $0.payload.faceCount < $1.payload.faceCount }) else { return nil }

        let time = formattedTime(busiest.signal.timestamp, calendar: calendar)
        let faces = busiest.payload.faceCount
        let text = faces == 1
            ? "There's one person in your \(time) photo — who is it?"
            : "There are \(faces) people in your \(time) photo — who were you with?"

        return GuidedQuestion(
            id: "people.\(busiest.payload.assetLocalIdentifier)",
            text: text,
            subject: .peopleInPhoto(faceCount: faces),
            photoAssetIdentifiers: [busiest.payload.assetLocalIdentifier],
            feelingPrompt: "How was it, being with them?"
        )
    }

    private static func assetIdentifiers(
        from photos: [(signal: DaySignal, payload: PhotoPayload)],
        near timestamp: Date,
        limit: Int = 3
    ) -> [String] {
        photos
            .filter { !$0.payload.isScreenshot }
            .filter { abs($0.signal.timestamp.timeIntervalSince(timestamp)) <= photoProximity }
            .prefix(limit)
            .map(\.payload.assetLocalIdentifier)
    }

    static func formattedTime(_ date: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
