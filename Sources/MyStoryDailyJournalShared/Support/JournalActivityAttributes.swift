import Foundation
import ActivityKit

/// The Live Activity's whole content model, deliberately this thin: per
/// §5, a Live Activity "shows the prompt only, never content." There is no
/// field here that could carry journal text, so there's nothing to leak
/// onto the Lock Screen even by accident.
struct JournalActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isJournaled: Bool
        var dateDescription: String
    }
}
