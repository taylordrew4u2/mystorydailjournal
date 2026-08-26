import Foundation
import SwiftData

/// A one-tap token (e.g. "Good", "Rough", "Busy") that can constitute a
/// valid entry by itself. Chip capture UI lands in a later milestone; the
/// model exists now so `DayRecord.tags` has somewhere to point.
@Model
final class Tag {
    var name: String = ""
    var createdAt: Date = Date.distantPast
    var dayRecords: [DayRecord]? = []

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }
}
