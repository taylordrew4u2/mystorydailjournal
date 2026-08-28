import Foundation
import SwiftData

/// Everything a set of guided answers does to a day besides becoming
/// prose. Runs automatically the moment the questions are finished — the
/// writer is never asked whether the day should absorb what they just
/// said:
///
/// - a place named in an answer replaces its address everywhere, and is
///   remembered for every future day at that address;
/// - people named in an answer are tagged on the day, and — when the
///   question was about the faces in a photo — recorded on that photo, so
///   later regenerations can say who was in the frame;
/// - the answers themselves come back rewritten, so the address the writer
///   was shown doesn't survive into the entry.
@MainActor
enum GuidedAnswerApplier {
    struct Outcome {
        var responses: [GuidedResponse]
        var baseText: String
        var renamedPlaces: [String: String]
        var taggedPeople: [String]
    }

    /// `chosenNames` is what the writer tapped from each question's name
    /// chips, one entry per question — a tap is as much a confirmation as
    /// typing the name.
    static func apply(
        questions: [GuidedQuestion],
        responses: [GuidedResponse],
        chosenNames: [[String]] = [],
        baseText: String,
        to record: DayRecord,
        in context: ModelContext
    ) -> Outcome {
        let confirmations = placeConfirmations(questions: questions, responses: responses)
        let replacements = PlaceRenamer.apply(confirmations, to: record, in: context)

        let renamedResponses = responses.map { response in
            var renamed = response
            renamed.answer = PlaceNameResolver.rename(response.answer, replacements: replacements)
            return renamed
        }

        // A name is worth tagging wherever it turns up — "Blue Bottle with
        // Dana" answers a question about a place and still says who was
        // there.
        let known = knownNames(for: record, questions: questions, extra: chosenNames.flatMap { $0 }, in: context)
        var tagged: [String] = []
        for (index, question) in questions.enumerated() {
            let answer = index < renamedResponses.count ? renamedResponses[index].answer : ""
            let chosen = index < chosenNames.count ? chosenNames[index] : []
            let confirmed = deduplicated(names(in: answer, among: known) + chosen)
            guard !confirmed.isEmpty else { continue }

            tag(confirmed, on: record, in: context)
            tagged += confirmed
            if case .peopleInPhoto = question.subject,
               let assetIdentifier = question.photoAssetIdentifiers.first {
                recordPeople(confirmed, onPhoto: assetIdentifier, of: record)
            }
        }

        try? context.save()

        return Outcome(
            responses: renamedResponses,
            baseText: PlaceNameResolver.rename(baseText, replacements: replacements),
            renamedPlaces: replacements,
            taggedPeople: deduplicated(tagged)
        )
    }

    /// An answer to "What's at 480 Larkin Street?" is a rename if a venue
    /// name can be read out of it; a shrug leaves the address alone.
    nonisolated static func placeConfirmations(
        questions: [GuidedQuestion],
        responses: [GuidedResponse]
    ) -> [PlaceConfirmation] {
        zip(questions, responses).compactMap { question, response in
            guard let place = question.renamablePlace,
                  let name = PlaceNameResolver.venueName(fromAnswer: response.answer),
                  name.compare(place.rawName, options: .caseInsensitive) != .orderedSame else { return nil }
            return PlaceConfirmation(
                rawName: place.rawName,
                confirmedName: name,
                latitude: place.latitude,
                longitude: place.longitude
            )
        }
    }

    /// Whole-word, case-insensitive matches of names the app already knows
    /// — deliberately not general name extraction: a name only lands on a
    /// day because the writer wrote a name the journal has seen before, or
    /// tapped it from the suggestions.
    nonisolated static func names(in text: String, among known: [String]) -> [String] {
        let haystack = text.lowercased()
        var found: [(offset: Int, name: String)] = []

        for name in known {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            var candidates = [trimmed.lowercased()]
            // "Dana" should still match a known "Dana Chen".
            if let firstWord = trimmed.split(separator: " ").first, firstWord.count >= 3 {
                candidates.append(String(firstWord).lowercased())
            }
            for candidate in candidates {
                guard let range = wholeWordRange(of: candidate, in: haystack) else { continue }
                found.append((haystack.distance(from: haystack.startIndex, to: range.lowerBound), trimmed))
                break
            }
        }

        return deduplicated(found.sorted { $0.offset < $1.offset }.map(\.name))
    }

    nonisolated private static func wholeWordRange(of needle: String, in haystack: String) -> Range<String.Index>? {
        var searchStart = haystack.startIndex
        while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            let startsCleanly = range.lowerBound == haystack.startIndex
                || !haystack[haystack.index(before: range.lowerBound)].isLetter
            let endsCleanly = range.upperBound == haystack.endIndex
                || !haystack[range.upperBound].isLetter
            if startsCleanly, endsCleanly { return range }
            guard range.upperBound < haystack.endIndex else { return nil }
            searchStart = range.upperBound
        }
        return nil
    }

    private static func knownNames(
        for record: DayRecord,
        questions: [GuidedQuestion],
        extra: [String],
        in context: ModelContext
    ) -> [String] {
        var names = questions.flatMap(\.nameSuggestions)
        names += extra
        names += (record.people ?? []).map(\.name)
        names += PeopleRepository.recentPeople(in: context, limit: 20).map(\.name)
        return deduplicated(names)
    }

    private static func tag(_ names: [String], on record: DayRecord, in context: ModelContext) {
        for name in names {
            let alreadyTagged = (record.people ?? []).contains {
                $0.name.compare(name, options: .caseInsensitive) == .orderedSame
            }
            guard !alreadyTagged else { continue }
            let person = PeopleRepository.findOrCreatePerson(named: name, in: context)
            PeopleRepository.toggle(person, on: record, in: context)
        }
    }

    /// Who the writer said was in a specific shot. Stored on the photo
    /// signal so a regenerated digest can name them instead of falling back
    /// to "two people in the frame".
    private static func recordPeople(_ names: [String], onPhoto assetIdentifier: String, of record: DayRecord) {
        for signal in record.signals ?? [] where signal.kind == .photo {
            guard var payload = signal.payload(as: PhotoPayload.self),
                  payload.assetLocalIdentifier == assetIdentifier else { continue }
            payload.personNames = deduplicated(payload.personNames + names)
            signal.setPayload(payload)
            return
        }
    }

    nonisolated private static func deduplicated(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            unique.append(trimmed)
        }
        return unique
    }
}
