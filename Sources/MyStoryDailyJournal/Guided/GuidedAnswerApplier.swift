import Foundation
import SwiftData

/// Everything a set of guided answers does to a day besides becoming
/// prose. Runs automatically the moment the questions are finished — the
/// writer is never asked whether the day should absorb what they just
/// said:
///
/// - a place named in an answer replaces its address everywhere, and is
///   remembered for every future day at that address;
/// - relationship answers are saved privately on the person record, without
///   adding visible day tags;
/// - the answers themselves come back rewritten, so the address the writer
///   was shown doesn't survive into the entry.
@MainActor
enum GuidedAnswerApplier {
    struct Outcome {
        var responses: [GuidedResponse]
        var baseText: String
        var renamedPlaces: [String: String]
        /// Places the writer said they were only walking past. Already
        /// lifted out of `baseText`; carried here so the rewrite is told
        /// not to put them back.
        var omittedPlaces: [String] = []
    }

    /// `chosenNames` is what the writer tapped from each question's name
    /// chips, one entry per question — a tap is as much a confirmation as
    /// typing the name. `placeChoices` is the same for the place options:
    /// the venue Maps found, the kind of place it was, or "just walking
    /// past."
    static func apply(
        questions: [GuidedQuestion],
        responses: [GuidedResponse],
        chosenNames: [[String]] = [],
        placeChoices: [PlaceChoice?] = [],
        baseText: String,
        to record: DayRecord,
        in context: ModelContext
    ) -> Outcome {
        // "Just walking past" first: a stop that never happened shouldn't be
        // renamed, aliased, or left in the text the entry is built from.
        var omittedPlaces: [String] = []
        for (index, question) in questions.enumerated() {
            guard let place = question.placeSubject,
                  index < placeChoices.count,
                  placeChoices[index]?.isPassingThrough == true else { continue }
            PlaceRenamer.markPassingThrough(placeNamed: place.rawName, on: record, in: context)
            omittedPlaces.append(place.rawName)
        }

        let confirmations = placeConfirmations(
            questions: questions,
            responses: responses,
            placeChoices: placeChoices
        )
        let replacements = PlaceRenamer.apply(confirmations, to: record, in: context)

        let renamedResponses = responses.map { response in
            var renamed = response
            renamed.answer = PlaceNameResolver.rename(response.answer, replacements: replacements)
            return renamed
        }

        for (index, question) in questions.enumerated() {
            let answer = index < renamedResponses.count ? renamedResponses[index].answer : ""
            guard case let .mentionedPerson(name) = question.subject else { continue }
            let relationship = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !relationship.isEmpty else { continue }

            let person = PeopleRepository.findOrCreatePerson(named: name, in: context)
            RelationshipPrompter.describe(
                person,
                relationship: relationship,
                now: .now,
                in: context
            )
        }

        try? context.save()

        var text = baseText
        for place in omittedPlaces {
            text = PlaceNameResolver.removingMentions(of: place, in: text)
        }

        return Outcome(
            responses: renamedResponses,
            baseText: PlaceNameResolver.rename(text, replacements: replacements),
            renamedPlaces: replacements,
            omittedPlaces: omittedPlaces
        )
    }

    /// What a place question settled. A tapped option wins — it's the
    /// writer pointing at the venue Maps found or saying what kind of place
    /// it was — and typing a name still works when no option fit. A shrug,
    /// or nothing at all, leaves the address alone.
    nonisolated static func placeConfirmations(
        questions: [GuidedQuestion],
        responses: [GuidedResponse],
        placeChoices: [PlaceChoice?] = []
    ) -> [PlaceConfirmation] {
        questions.enumerated().compactMap { index, question in
            guard let place = question.placeSubject else { return nil }
            let choice = index < placeChoices.count ? placeChoices[index] : nil
            if choice?.isPassingThrough == true { return nil }

            let answer = index < responses.count ? responses[index].answer : ""
            // A tapped option names any place; a typed answer only renames
            // one the geocoder never named properly.
            let name = choice?.confirmedName
                ?? (question.renamablePlace == nil ? nil : PlaceNameResolver.venueName(fromAnswer: answer))
            guard let name, !name.isEmpty,
                  name.compare(place.rawName, options: .caseInsensitive) != .orderedSame else { return nil }

            return PlaceConfirmation(
                rawName: place.rawName,
                confirmedName: name,
                latitude: place.latitude,
                longitude: place.longitude,
                kind: choice?.kind,
                categoryLabel: choice?.categoryLabel
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
