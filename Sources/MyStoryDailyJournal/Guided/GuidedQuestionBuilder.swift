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
    /// How many signal-specific questions to ask before the two open ones.
    /// Address questions are exempt — being asked where you were is the
    /// point, and there are rarely many in a day.
    private static let specificQuestionLimit = 6

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

        let attendeeNames = signals
            .filter { $0.kind == .calendar }
            .compactMap { $0.payload(as: CalendarPayload.self) }
            .flatMap(\.attendeeNames)

        var addressQuestions: [GuidedQuestion] = []
        var otherQuestions: [GuidedQuestion] = []

        for question in placeQuestions(signals: signals, photos: photos, aliases: aliases) {
            if question.renamablePlace != nil {
                addressQuestions.append(question)
            } else {
                otherQuestions.append(question)
            }
        }

        otherQuestions += eventQuestions(signals: signals, photos: photos, attendeeNames: attendeeNames)
        if let photoQuestion = photoQuestion(photos: photos) {
            otherQuestions.append(photoQuestion)
        }
        if let peopleQuestion = peopleInPhotoQuestion(photos: photos, calendar: calendar, attendeeNames: attendeeNames) {
            otherQuestions.append(peopleQuestion)
        }
        if let activity = signals.first(where: { $0.kind == .activity })?.payload(as: ActivityPayload.self),
           !activity.workoutSummaries.isEmpty {
            otherQuestions.append(GuidedQuestion(
                id: "activity",
                text: "How did your workout go?",
                subject: .activity,
                feelingPrompt: "How did your body feel afterwards?"
            ))
        }

        let specific = addressQuestions + otherQuestions.prefix(max(0, specificQuestionLimit - addressQuestions.count))
        return specific + openQuestions
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

        let visits = signals
            .filter { $0.kind == .visit }
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { signal -> (signal: DaySignal, payload: VisitPayload)? in
                guard let payload = signal.payload(as: VisitPayload.self) else { return nil }
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
        photos: [(signal: DaySignal, payload: PhotoPayload)],
        attendeeNames: [String]
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
                    nameSuggestions: payload.attendeeNames.isEmpty ? attendeeNames : payload.attendeeNames,
                    feelingPrompt: "How did it leave you feeling?"
                )
            }
            .prefix(2)
            .map { $0 }
    }

    private static func eventQuestionText(for payload: CalendarPayload) -> String {
        if let location = payload.location {
            return "How did \"\(payload.title)\" at \(location) go, and who was there?"
        }
        if !payload.attendeeNames.isEmpty {
            return "How did \"\(payload.title)\" go, and who was with you?"
        }
        return "How did \"\(payload.title)\" go?"
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
        calendar: Calendar,
        attendeeNames: [String]
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
            nameSuggestions: Array(Set(attendeeNames)).sorted(),
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
