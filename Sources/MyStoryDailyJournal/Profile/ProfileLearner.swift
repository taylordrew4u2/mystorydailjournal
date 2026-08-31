import Foundation
import SwiftData

/// Learns the person from their own journal and keeps what it learns.
///
/// The app used to work out who mattered and how the writer sounded from
/// scratch every time it wrote a line, which meant it could never know
/// anything that took more than a month to become visible. This builds a
/// standing picture instead — people and how they cluster, the places that
/// recur and what they are, the rhythms of a week, the themes the journal
/// returns to, and the writer's own voice — stored as `ProfileFact`s that
/// deepen as the journal grows.
///
/// Everything is derived on-device from days the writer already has, every
/// fact says how many days it rests on, and every fact can be muted or
/// deleted in Settings. Nothing about anyone but the writer is inferred,
/// and nothing leaves the phone.
enum ProfileLearner {
    /// How far back a learning pass reads. Long enough for a season's
    /// rhythms to show, short enough that a pass stays cheap.
    static let lookbackDays = 180

    /// A pattern needs this many days behind it before it's worth telling
    /// the writing about — below that it's a coincidence, not a habit.
    static let minimumObservations = 3

    /// How often a background pass is worth repeating. A month-long
    /// backfill generates a day at a time; re-reading the whole journal
    /// after each one would be thirty passes for one picture.
    static let relearnInterval: TimeInterval = 6 * 60 * 60

    /// Where the "learn about me" switch lives. Owned here rather than on
    /// `SettingsStore` because this runs wherever the digest engine runs,
    /// not only on the main actor — `SettingsStore` reads and writes the
    /// same key, so there is still one stored value.
    static let learningEnabledKey = "settings.profileLearningEnabled"

    private static let lastLearnedKey = "profile.lastLearnedAt"

    /// Whether the writer has left learning on. Absent means on: the app
    /// has always read recent entries to match their voice, and this makes
    /// that memory rather than a fresh guess each time.
    static func isLearningEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: learningEnabledKey) as? Bool ?? true
    }

    /// The background path: learns only if the picture has gone stale, so a
    /// 30-day backfill costs one pass rather than thirty.
    @discardableResult
    static func learnIfNeeded(
        in context: ModelContext,
        now: Date = .now,
        defaults: UserDefaults = .standard
    ) -> [ProfileFact] {
        guard isLearningEnabled(defaults: defaults) else { return [] }
        if let last = defaults.object(forKey: lastLearnedKey) as? Date,
           now.timeIntervalSince(last) < relearnInterval {
            return []
        }
        return learn(in: context, now: now, defaults: defaults)
    }

    /// Re-learns the whole picture from the journal. Idempotent: running it
    /// twice against the same days leaves the same facts, with the writer's
    /// own pins and mutes untouched.
    @discardableResult
    static func learn(
        in context: ModelContext,
        now: Date = .now,
        defaults: UserDefaults = .standard
    ) -> [ProfileFact] {
        guard isLearningEnabled(defaults: defaults) else { return [] }
        defaults.set(now, forKey: lastLearnedKey)

        let days = recentDays(in: context, now: now)
        guard !days.isEmpty else { return [] }

        var learned: [Observation] = []
        learned += peopleObservations(in: days)
        learned += placeObservations(in: days)
        learned += rhythmObservations(in: days)
        learned += themeObservations(in: days)
        learned += voiceObservations(in: days)

        return upsert(learned, in: context)
    }

    /// One observation before it becomes (or updates) a stored fact.
    struct Observation: Equatable {
        var kind: ProfileFactKind
        var subject: String
        var detail: String
        var observationCount: Int
        var firstObserved: Date
        var lastObserved: Date
    }

    // MARK: - Reading the journal

    private static func recentDays(in context: ModelContext, now: Date) -> [DayRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: now) ?? .distantPast
        var descriptor = FetchDescriptor<DayRecord>(
            predicate: #Predicate { $0.date >= cutoff },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = lookbackDays
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - People

    /// Who recurs, who they turn up with, and where. Only ever the writer's
    /// own tags — a name is here because the writer put it on a day.
    private static func peopleObservations(in days: [DayRecord]) -> [Observation] {
        var daysWith: [String: [DayRecord]] = [:]
        for day in days {
            for person in day.people ?? [] {
                daysWith[person.name, default: []].append(day)
            }
        }

        return daysWith.compactMap { name, shared in
            guard shared.count >= minimumObservations else { return nil }

            var parts = ["appears on \(shared.count) days"]
            if let places = commonPlaces(in: shared, limit: 2), !places.isEmpty {
                parts.append("usually around \(list(places))")
            }
            let companions = shared
                .flatMap { ($0.people ?? []).map(\.name) }
                .filter { $0 != name }
                .frequencies()
                .filter { $0.value >= 2 }
                .sorted { $0.value > $1.value }
                .prefix(2)
                .map(\.key)
            if !companions.isEmpty {
                parts.append("often with \(list(Array(companions)))")
            }
            if let pattern = weekdayPattern(of: shared.map(\.date)) {
                parts.append(pattern)
            }

            let dates = shared.map(\.date)
            return Observation(
                kind: .person,
                subject: name,
                detail: "\(name) — \(parts.joined(separator: ", ")).",
                observationCount: shared.count,
                firstObserved: dates.min() ?? .now,
                lastObserved: dates.max() ?? .now
            )
        }
    }

    private static func commonPlaces(in days: [DayRecord], limit: Int) -> [String]? {
        let names = days.flatMap { day in
            (day.signals ?? [])
                .filter { $0.kind == .visit }
                .compactMap { $0.payload(as: VisitPayload.self) }
                .filter { !$0.isPassingThrough }
                .map(\.placeName)
        }
        guard !names.isEmpty else { return nil }
        return names.frequencies()
            .filter { $0.value >= 2 }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }

    // MARK: - Places

    /// The places a life actually happens in, with what the writer said
    /// each one is (`PlaceKind`) and when they tend to be there.
    private static func placeObservations(in days: [DayRecord]) -> [Observation] {
        var visitsByPlace: [String: [(date: Date, timestamp: Date, kind: PlaceKind?, category: String?)]] = [:]

        for day in days {
            for signal in day.signals ?? [] where signal.kind == .visit {
                guard let payload = signal.payload(as: VisitPayload.self), !payload.isPassingThrough else { continue }
                visitsByPlace[payload.placeName, default: []].append((
                    date: day.date,
                    timestamp: signal.timestamp,
                    kind: payload.placeKindRaw.flatMap(PlaceKind.init(rawValue:)),
                    category: payload.categoryLabel
                ))
            }
        }

        return visitsByPlace.compactMap { name, visits in
            guard visits.count >= minimumObservations else { return nil }

            var parts: [String] = []
            if let category = visits.compactMap(\.category).first {
                parts.append("a \(category)")
            } else if let kind = visits.compactMap(\.kind).first, !kind.isPassingThrough {
                parts.append(kind.displayName.lowercased())
            }
            parts.append("\(visits.count) days")
            if let pattern = weekdayPattern(of: visits.map(\.date)) {
                parts.append(pattern)
            }
            if let time = dominantPartOfDay(of: visits.map(\.timestamp)) {
                parts.append("usually \(time)")
            }

            let dates = visits.map(\.date)
            return Observation(
                kind: .place,
                subject: name,
                detail: "\(name) — \(parts.joined(separator: ", ")).",
                observationCount: visits.count,
                firstObserved: dates.min() ?? .now,
                lastObserved: dates.max() ?? .now
            )
        }
    }

    // MARK: - Rhythms

    private static func rhythmObservations(in days: [DayRecord]) -> [Observation] {
        var observations: [Observation] = []
        let dates = days.map(\.date)
        let first = dates.min() ?? .now
        let last = dates.max() ?? .now

        let written = days.filter(\.isUserWritten)
        if written.count >= minimumObservations,
           let hour = dominantPartOfDay(of: written.map(\.editedAt)) {
            observations.append(Observation(
                kind: .rhythm,
                subject: "writing time",
                detail: "Tends to write \(hour).",
                observationCount: written.count,
                firstObserved: first,
                lastObserved: last
            ))
        }

        let workoutDays = days.filter { day in
            (day.signals ?? [])
                .compactMap { $0.payload(as: ActivityPayload.self) }
                .contains { !$0.workoutSummaries.isEmpty }
        }
        if workoutDays.count >= minimumObservations {
            var detail = "Works out on \(workoutDays.count) of the last \(days.count) days"
            if let pattern = weekdayPattern(of: workoutDays.map(\.date)) {
                detail += ", \(pattern)"
            }
            observations.append(Observation(
                kind: .rhythm,
                subject: "exercise",
                detail: detail + ".",
                observationCount: workoutDays.count,
                firstObserved: first,
                lastObserved: last
            ))
        }

        return observations
    }

    // MARK: - Themes

    /// What the journal keeps returning to: the writer's own tags, and what
    /// their photos are of.
    private static func themeObservations(in days: [DayRecord]) -> [Observation] {
        var observations: [Observation] = []

        var tagDays: [String: [Date]] = [:]
        for day in days {
            for tag in day.tags ?? [] {
                tagDays[tag.name, default: []].append(day.date)
            }
        }
        for (tag, dates) in tagDays where dates.count >= minimumObservations {
            observations.append(Observation(
                kind: .theme,
                subject: tag,
                detail: "Tags days \"\(tag)\" often — \(dates.count) times.",
                observationCount: dates.count,
                firstObserved: dates.min() ?? .now,
                lastObserved: dates.max() ?? .now
            ))
        }

        var sceneDays: [String: [Date]] = [:]
        for day in days {
            let labels = Set(
                (day.signals ?? [])
                    .filter { $0.kind == .photo }
                    .compactMap { $0.payload(as: PhotoPayload.self) }
                    .flatMap(\.sceneLabels)
            )
            for label in labels {
                sceneDays[label, default: []].append(day.date)
            }
        }
        for (label, dates) in sceneDays where dates.count >= minimumObservations {
            observations.append(Observation(
                kind: .theme,
                subject: label,
                detail: "Photographs \(label) often — on \(dates.count) days.",
                observationCount: dates.count,
                firstObserved: dates.min() ?? .now,
                lastObserved: dates.max() ?? .now
            ))
        }

        return observations
    }

    // MARK: - Voice

    /// How the writer actually writes, measured from what they wrote
    /// themselves — never from a digest the app composed.
    private static func voiceObservations(in days: [DayRecord]) -> [Observation] {
        let entries = days
            .filter(\.isUserWritten)
            .map(\.bodyText)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard entries.count >= minimumObservations else { return [] }

        let dates = days.filter(\.isUserWritten).map(\.date)
        let first = dates.min() ?? .now
        let last = dates.max() ?? .now
        var observations: [Observation] = []

        let averageLength = entries.map(\.count).reduce(0, +) / entries.count
        let lengthDetail: String = switch averageLength {
        case ..<200: "Keeps entries short and to the point."
        case ..<800: "Writes a few unhurried paragraphs."
        default: "Writes long, detailed entries."
        }
        observations.append(Observation(
            kind: .voice,
            subject: "entry length",
            detail: lengthDetail,
            observationCount: entries.count,
            firstObserved: first,
            lastObserved: last
        ))

        let sentences = entries.flatMap { $0.split(whereSeparator: { ".!?".contains($0) }) }
        if !sentences.isEmpty {
            let averageWords = sentences.map { $0.split(separator: " ").count }.reduce(0, +) / sentences.count
            observations.append(Observation(
                kind: .voice,
                subject: "sentences",
                detail: averageWords <= 12
                    ? "Writes in short sentences."
                    : "Writes in long, flowing sentences.",
                observationCount: entries.count,
                firstObserved: first,
                lastObserved: last
            ))
        }

        let joined = entries.joined(separator: " ")
        if !joined.contains(where: { $0.unicodeScalars.contains { $0.properties.isEmoji && $0.value > 0x238C } }) {
            observations.append(Observation(
                kind: .voice,
                subject: "emoji",
                detail: "Never uses emoji.",
                observationCount: entries.count,
                firstObserved: first,
                lastObserved: last
            ))
        }

        let distinctive = distinctiveWords(in: entries)
        if !distinctive.isEmpty {
            observations.append(Observation(
                kind: .voice,
                subject: "words",
                detail: "Words they reach for: \(list(distinctive)).",
                observationCount: entries.count,
                firstObserved: first,
                lastObserved: last
            ))
        }

        return observations
    }

    /// The words this writer uses far more than a generic diary would —
    /// their own vocabulary, minus the words everyone uses.
    static func distinctiveWords(in entries: [String], limit: Int = 5) -> [String] {
        let counts = entries
            .flatMap { entry in
                entry.lowercased()
                    .split { !$0.isLetter && $0 != "'" }
                    .map(String.init)
            }
            .filter { $0.count > 3 && !stopwords.contains($0) }
            .frequencies()

        return counts
            .filter { $0.value >= minimumObservations }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }

    // MARK: - Storing

    /// Updates what's already known and adds what isn't, matching on kind +
    /// subject. A fact the writer muted stays muted however often it comes
    /// back, and `firstObserved` only ever reaches further back — that's the
    /// part that makes this a memory rather than a snapshot.
    @discardableResult
    private static func upsert(_ observations: [Observation], in context: ModelContext) -> [ProfileFact] {
        let existing = (try? context.fetch(FetchDescriptor<ProfileFact>())) ?? []
        var byIdentity: [String: ProfileFact] = [:]
        for fact in existing {
            byIdentity[identity(kind: fact.kind, subject: fact.subject)] = fact
        }

        var touched: [ProfileFact] = []
        for observation in observations {
            let key = identity(kind: observation.kind, subject: observation.subject)
            if let fact = byIdentity[key] {
                fact.detail = observation.detail
                fact.observationCount = observation.observationCount
                fact.firstObserved = min(fact.firstObserved, observation.firstObserved)
                fact.lastObserved = max(fact.lastObserved, observation.lastObserved)
                touched.append(fact)
            } else {
                let fact = ProfileFact(
                    kind: observation.kind,
                    subject: observation.subject,
                    detail: observation.detail,
                    observationCount: observation.observationCount,
                    firstObserved: observation.firstObserved,
                    lastObserved: observation.lastObserved
                )
                context.insert(fact)
                byIdentity[key] = fact
                touched.append(fact)
            }
        }

        try? context.save()
        return touched
    }

    private static func identity(kind: ProfileFactKind, subject: String) -> String {
        "\(kind.rawValue)|\(subject.lowercased())"
    }

    /// Wipes everything the app has worked out. The journal itself is
    /// untouched — this only forgets the conclusions.
    static func forgetEverything(in context: ModelContext, defaults: UserDefaults = .standard) {
        for fact in (try? context.fetch(FetchDescriptor<ProfileFact>())) ?? [] {
            context.delete(fact)
        }
        defaults.removeObject(forKey: lastLearnedKey)
        try? context.save()
    }

    // MARK: - Shared helpers

    /// "mostly on Tuesdays and Thursdays" — only when the days really do
    /// cluster, so a habit is claimed only where there is one.
    static func weekdayPattern(of dates: [Date], calendar: Calendar = .current) -> String? {
        guard dates.count >= minimumObservations else { return nil }
        let counts = dates.map { calendar.component(.weekday, from: $0) }.frequencies()
        let ranked = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        let top = Array(ranked.prefix(2))
        let covered = top.map(\.value).reduce(0, +)
        guard Double(covered) / Double(dates.count) >= 0.6 else { return nil }

        let names = top.filter { $0.value >= 2 }.map { weekdayName($0.key, calendar: calendar) }
        guard !names.isEmpty else { return nil }
        return "mostly on \(list(names))"
    }

    private static func weekdayName(_ weekday: Int, calendar: Calendar) -> String {
        let symbols = calendar.weekdaySymbols
        let index = weekday - 1
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index] + "s"
    }

    static func dominantPartOfDay(of dates: [Date], calendar: Calendar = .current) -> String? {
        guard !dates.isEmpty else { return nil }
        let buckets = dates.map { partOfDay(for: $0, calendar: calendar) }.frequencies()
        guard let top = buckets.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }) else {
            return nil
        }
        guard Double(top.value) / Double(dates.count) >= 0.5 else { return nil }
        return top.key
    }

    private static func partOfDay(for date: Date, calendar: Calendar) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: "in the morning"
        case 12..<17: "in the afternoon"
        case 17..<22: "in the evening"
        default: "late at night"
        }
    }

    private static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: items.dropLast().joined(separator: ", ") + ", and \(items.last!)"
        }
    }

    /// Words common enough in any diary that using them says nothing about
    /// this particular writer.
    private static let stopwords: Set<String> = [
        "that", "this", "with", "have", "just", "were", "they", "them", "then",
        "than", "there", "their", "about", "would", "could", "should", "which",
        "what", "when", "from", "into", "some", "much", "more", "very", "really",
        "today", "yesterday", "tomorrow", "morning", "afternoon", "evening",
        "night", "went", "back", "time", "like", "been", "being", "over",
        "after", "before", "still", "even", "also", "because", "around",
        "little", "thing", "things", "good", "nice", "well", "made", "make",
        "take", "took", "getting", "going", "again", "though", "felt",
    ]
}

private extension Sequence where Element: Hashable {
    func frequencies() -> [Element: Int] {
        reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }
}
