import Foundation

/// Codable payloads stored in `DaySignal.payloadData` (build spec §10:
/// "identifiers and derived summaries only"). One type per `DaySignalKind`
/// that has a concrete provider so far.
struct VisitPayload: Codable {
    var placeName: String
    var latitude: Double
    var longitude: Double
    var isFullAccuracy: Bool
}

struct PhotoPayload: Codable {
    var assetLocalIdentifier: String
    var isScreenshot: Bool

    /// Derived from the asset's own metadata (§10: summaries, not content):
    /// where and roughly when the shot was taken. All optional — screenshots
    /// and location-stripped photos simply leave them nil, and payloads
    /// stored before these fields existed decode fine without them.
    var placeName: String? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
}

struct CalendarPayload: Codable {
    var eventIdentifier: String
    var title: String
    var attendeeNames: [String]

    /// The event's own location field, when the organizer filled one in —
    /// a derived summary (§10). Optional so payloads stored before this
    /// field existed decode fine without it.
    var location: String? = nil
}

struct ActivityPayload: Codable {
    var stepCount: Int
    var distanceMeters: Double
    var workoutSummaries: [String]
    var sleepHours: Double = 0
}

struct MediaPayload: Codable {
    var titles: [String]
}

struct WeatherPayload: Codable {
    var conditionDescription: String
    var highTemperatureCelsius: Double?
    var lowTemperatureCelsius: Double?
}

/// Notes/Messages content pushed in, regardless of which path delivered it
/// — the Share Extension (M7) or a Shortcuts automation (M8). Storage
/// shape is identical either way (§10).
struct SharedItemPayload: Codable {
    var title: String?
    var text: String
    var sourceApp: String?
}

/// A file noticed in the user's one watched folder (§3, §4). Just a name —
/// never the file's contents.
struct FileWatchPayload: Codable {
    var fileName: String
    var folderName: String
}

/// Something the user manually pinned to a day from the entry view — a
/// note, photos/screenshots picked from the library, or a file. Survives
/// digest regeneration (it's a pushed kind the engine never deletes) and
/// gets folded into the regenerated text. Same storage rules as everything
/// else (§10): note text the user typed themselves, asset identifiers, and
/// file names — never file or image contents.
struct AttachmentPayload: Codable {
    enum Kind: String, Codable {
        case note
        case photo
        case file
    }

    var kind: Kind
    var text: String? = nil
    var assetLocalIdentifier: String? = nil
    var fileName: String? = nil
}
