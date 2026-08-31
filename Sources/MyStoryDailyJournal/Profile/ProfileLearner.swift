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
        var byName: [String: Person] = [:]
        for day in days {
            for person in day.people ?? [] {
                daysWith[person.name, default: []].append(day)
                byName[person.name] = person
            }
        }

        return daysWith.compactMap { name, shared in
            guard shared.count >= minimumObservations else { return nil }

            var parts: [String] = []
            // What the writer said about them, when they've been asked —
            // this is the difference between an entry that knows Dana is
            // your sister and one repeating a name back at you.
            if let described = byName[name]?.descriptionForWriting {
                parts.append(described)
            }
            parts.append("appears on \(shared.count) days")
            if let places = commonPlaces(in: shared, limit: 2), !places.isEmpty {
                parts.append("usually around \(list(places))")
            }
            var companionCounts: [String: Int] = [:]
            for day in shared {
                for person in day.people ?? [] where person.name != name {
                    companionCounts[person.name, default: 0] += 1
                }
            }
            let companions: [String] = topKeys(of: companionCounts, atLeast: 2, limit: 2)
            if !companions.isEmpty {
                parts.append("often with \(list(companions))")
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
        var counts: [String: Int] = [:]
        for day in days {
            for signal in day.signals ?? [] where signal.kind == .visit {
                guard let payload = signal.payload(as: VisitPayload.self), !payload.isPassingThrough else { continue }
                counts[payload.placeName, default: 0] += 1
            }
        }
        guard !counts.isEmpty else { return nil }
        return topKeys(of: counts, atLeast: 2, limit: limit)
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
            var labels = Set<String>()
            for signal in day.signals ?? [] where signal.kind == .photo {
                guard let payload = signal.payload(as: PhotoPayload.self) else { continue }
                labels.formUnion(payload.sceneLabels)
            }
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
        var entries: [String] = []
        var dates: [Date] = []
        // Captions from an imported social archive count here for the same
        // reason the day's own body text does, and for the only reason
        // anything counts here: the writer wrote them. They are also the
        // one voice source that exists for days written before the app did.
        for day in days {
            for signal in day.signals ?? [] where signal.kind == .socialPost {
                guard let post = signal.payload(as: SocialPostPayload.self) else { continue }
                let caption = post.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !caption.isEmpty {
                    entries.append(caption)
                    dates.append(day.date)
                }
            }
        }

        for day in days where day.isUserWritten {
            dates.append(day.date)
            let text: String = day.bodyText
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                entries.append(text)
            }
        }
        guard entries.count >= minimumObservations else { return [] }

        let first = dates.min() ?? .now
        let last = dates.max() ?? .now
        var observations: [Observation] = []

        var totalLength = 0
        for entry in entries {
            totalLength += entry.count
        }
        let averageLength: Int = totalLength / entries.count
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

        var sentenceCount = 0
        var wordCount = 0
        for entry in entries {
            for sentence in entry.split(whereSeparator: { ".!?".contains($0) }) {
                sentenceCount += 1
                wordCount += sentence.split(separator: " ").count
            }
        }
        if sentenceCount > 0 {
            let averageWords: Int = wordCount / sentenceCount
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

        if !entries.contains(where: containsEmoji) {
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
        var counts: [String: Int] = [:]
        for entry in entries {
            let lowered: String = entry.lowercased()
            for piece in lowered.split(whereSeparator: { !$0.isLetter && $0 != "'" }) {
                let word = String(piece)
                guard word.count > 3, !stopwords.contains(word) else { continue }
                counts[word, default: 0] += 1
            }
        }
        return topKeys(of: counts, atLeast: minimumObservations, limit: limit)
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
        var counts: [Int: Int] = [:]
        for date in dates {
            let weekday: Int = calendar.component(.weekday, from: date)
            counts[weekday, default: 0] += 1
        }

        var ranked: [(weekday: Int, count: Int)] = []
        for (weekday, count) in counts {
            ranked.append((weekday: weekday, count: count))
        }
        ranked.sort { left, right in
            if left.count != right.count { return left.count > right.count }
            return left.weekday < right.weekday
        }

        var covered = 0
        var names: [String] = []
        for entry in ranked.prefix(2) {
            covered += entry.count
            if entry.count >= 2 {
                names.append(weekdayName(entry.weekday, calendar: calendar))
            }
        }
        guard Double(covered) / Double(dates.count) >= 0.6, !names.isEmpty else { return nil }
        return "mostly on \(list(names))"
    }

    /// The sentence built around this is English ("mostly on", "usually"),
    /// so the weekday name has to be too. A calendar carries no locale of
    /// its own unless one is set -- `Calendar(identifier:)` gives exactly
    /// that -- and `weekdaySymbols` then resolves to abbreviated root-locale
    /// forms, so pluralizing produced "Tues" rather than "Tuesdays".
    private static func weekdayName(_ weekday: Int, calendar: Calendar) -> String {
        var calendar = calendar
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let symbols = calendar.weekdaySymbols
        let index = weekday - 1
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index] + "s"
    }

    static func dominantPartOfDay(of dates: [Date], calendar: Calendar = .current) -> String? {
        guard !dates.isEmpty else { return nil }
        var buckets: [String: Int] = [:]
        for date in dates {
            let bucket: String = partOfDay(for: date, calendar: calendar)
            buckets[bucket, default: 0] += 1
        }

        var best = ""
        var bestCount = 0
        for (bucket, count) in buckets where count > bestCount || (count == bestCount && bucket < best) {
            best = bucket
            bestCount = count
        }
        guard bestCount > 0, Double(bestCount) / Double(dates.count) >= 0.5 else { return nil }
        return best
    }

    private static func partOfDay(for date: Date, calendar: Calendar) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: "in the morning"
        case 12..<17: "in the afternoon"
        case 17..<22: "in the evening"
        default: "late at night"
        }
    }

    /// The most-seen keys of a tally, ties broken alphabetically so the same
    /// journal always produces the same sentence. Written out longhand
    /// because the equivalent `.filter.sorted.prefix.map` chain is one of
    /// the shapes the Swift type checker gives up on.
    private static func topKeys(of counts: [String: Int], atLeast minimum: Int, limit: Int) -> [String] {
        var ranked: [(key: String, count: Int)] = []
        for (key, count) in counts where count >= minimum {
            ranked.append((key: key, count: count))
        }
        ranked.sort { left, right in
            if left.count != right.count { return left.count > right.count }
            return left.key < right.key
        }

        var keys: [String] = []
        for entry in ranked.prefix(limit) {
            keys.append(entry.key)
        }
        return keys
    }

    /// Deliberately not a one-liner over `unicodeScalars`: nesting that
    /// predicate inside another closure is what made this file time out.
    private static func containsEmoji(_ text: String) -> Bool {
        for scalar in text.unicodeScalars where scalar.properties.isEmoji && scalar.value > 0x238C {
            return true
        }
        return false
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
