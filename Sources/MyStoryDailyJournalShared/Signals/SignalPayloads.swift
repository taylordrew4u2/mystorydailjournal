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
}

struct CalendarPayload: Codable {
    var eventIdentifier: String
    var title: String
    var attendeeNames: [String]
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
