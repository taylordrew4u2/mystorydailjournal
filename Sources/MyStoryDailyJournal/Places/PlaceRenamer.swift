import Foundation
import SwiftData

/// One place the writer has named: the address the geocoder produced, the
/// name they gave it, and where it was.
struct PlaceConfirmation: Equatable, Sendable {
    var rawName: String
    var confirmedName: String
    var latitude: Double?
    var longitude: Double?
    /// What the writer said the place was, when they defined it from the
    /// options rather than typing a name.
    var kind: PlaceKind? = nil
    /// What Maps calls it ("comedy club", "café").
    var categoryLabel: String? = nil
}

/// Applies a confirmed venue name everywhere the old address survives: the
/// alias store (so future days are named without asking again), the day's
/// stored signals (so regenerating the day never brings the address back),
/// and the entry text itself.
///
/// Runs automatically the moment a guided answer names a place — the
/// writer is never asked whether they'd like the change made.
@MainActor
enum PlaceRenamer {
    /// Records each confirmation and rewrites the day's signals in place.
    /// Returns the address-to-name map to run over any text that still
    /// mentions the old name.
    @discardableResult
    static func apply(
        _ confirmations: [PlaceConfirmation],
        to record: DayRecord,
        in context: ModelContext
    ) -> [String: String] {
        var replacements: [String: String] = [:]

        for confirmation in confirmations {
            let raw = confirmation.rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = confirmation.confirmedName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, !name.isEmpty,
                  raw.compare(name, options: .caseInsensitive) != .orderedSame else { continue }

            PlaceAliasStore.record(
                name: name,
                for: raw,
                latitude: confirmation.latitude,
                longitude: confirmation.longitude
            )
            replacements[raw] = name
            rewriteSignals(
                of: record,
                from: raw,
                to: name,
                kind: confirmation.kind,
                categoryLabel: confirmation.categoryLabel
            )
        }

        guard !replacements.isEmpty else { return [:] }

        record.bodyText = PlaceNameResolver.rename(record.bodyText, replacements: replacements)
        record.notesText = PlaceNameResolver.rename(record.notesText, replacements: replacements)
        try? context.save()
        return replacements
    }

    /// "Just walking past" — the stop stays on the record but leaves the
    /// story: the visit is flagged so no future digest names it, and the
    /// sentence that named it is lifted out of the text the entry is being
    /// built from. Nothing is remembered device-wide: passing a place today
    /// says nothing about the next time the writer stops there.
    @discardableResult
    static func markPassingThrough(
        placeNamed rawName: String,
        on record: DayRecord,
        in context: ModelContext
    ) -> Bool {
        let raw = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }

        var marked = false
        for signal in record.signals ?? [] where signal.kind == .visit {
            guard var payload = signal.payload(as: VisitPayload.self),
                  payload.placeName.compare(raw, options: .caseInsensitive) == .orderedSame else { continue }
            payload.isPassingThrough = true
            payload.placeKindRaw = PlaceKind.walkingPast.rawValue
            signal.setPayload(payload)
            marked = true
        }

        record.bodyText = PlaceNameResolver.removingMentions(of: raw, in: record.bodyText)
        try? context.save()
        return marked
    }

    /// Every payload that carries a place name gets the new one, so the
    /// next digest regeneration composes from the venue rather than the
    /// address. The original is kept on visits (`rawPlaceName`) — it's what
    /// a future geocode will produce again, and what the alias is keyed on.
    private static func rewriteSignals(
        of record: DayRecord,
        from raw: String,
        to name: String,
        kind: PlaceKind? = nil,
        categoryLabel: String? = nil
    ) {
        for signal in record.signals ?? [] {
            switch signal.kind {
            case .visit:
                guard var payload = signal.payload(as: VisitPayload.self),
                      payload.placeName.compare(raw, options: .caseInsensitive) == .orderedSame else { continue }
                payload.rawPlaceName = payload.rawPlaceName ?? payload.placeName
                payload.placeName = name
                payload.placeKindRaw = kind?.rawValue ?? payload.placeKindRaw
                payload.categoryLabel = categoryLabel ?? payload.categoryLabel
                signal.setPayload(payload)
            case .photo:
                guard var payload = signal.payload(as: PhotoPayload.self),
                      let placeName = payload.placeName,
                      placeName.compare(raw, options: .caseInsensitive) == .orderedSame else { continue }
                payload.placeName = name
                signal.setPayload(payload)
            case .calendar:
                guard var payload = signal.payload(as: CalendarPayload.self),
                      let location = payload.location,
                      location.compare(raw, options: .caseInsensitive) == .orderedSame else { continue }
                payload.location = name
                signal.setPayload(payload)
            default:
                continue
            }
        }
    }
}
