import Foundation
import SwiftData

/// The category of a background signal folded into an auto-generated digest.
/// New providers (see `Signals/DaySignalProvider.swift`) each own one kind.
enum DaySignalKind: String, Codable, Sendable {
    case visit
    case photo
    case calendar
    case activity
    case media
    case weather
    case sharedItem
    case screenTime
    case fileWatch
    case attachment
}

/// A single piece of evidence contributed toward a day's digest.
///
/// `payload` stores identifiers and derived summaries only (e.g. a `PHAsset`
/// local identifier, an `EKEvent` identifier, a cached place name) — never
/// copies of the underlying content. See build spec §10.
@Model
final class DaySignal {
    var kindRaw: String = DaySignalKind.visit.rawValue
    var timestamp: Date = Date.distantPast
    var payloadData: Data?

    var dayRecord: DayRecord?

    var kind: DaySignalKind {
        get { DaySignalKind(rawValue: kindRaw) ?? .visit }
        set { kindRaw = newValue.rawValue }
    }

    init(kind: DaySignalKind, timestamp: Date = .now, payloadData: Data? = nil) {
        self.kindRaw = kind.rawValue
        self.timestamp = timestamp
        self.payloadData = payloadData
    }

    /// Decode `payloadData` as a specific `Codable` payload type.
    func payload<T: Decodable>(as type: T.Type) -> T? {
        guard let payloadData else { return nil }
        return try? JSONDecoder().decode(type, from: payloadData)
    }

    /// Encode and store a `Codable` payload.
    func setPayload<T: Encodable>(_ value: T) {
        payloadData = try? JSONEncoder().encode(value)
    }
}
