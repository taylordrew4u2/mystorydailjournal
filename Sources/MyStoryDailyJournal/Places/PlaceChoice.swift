import Foundation

/// What the writer tapped when a guided question asked them to define a
/// place: the real venue Maps found there, what kind of place it was, or
/// "just walking past" for a stop that was never a visit at all.
enum PlaceChoice: Equatable, Sendable {
    case venue(name: String, categoryLabel: String? = nil)
    case kind(PlaceKind)

    /// What the entry should call this place — nil when it shouldn't be
    /// named at all.
    var confirmedName: String? {
        switch self {
        case .venue(let name, _):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .kind(let kind):
            return kind.isPassingThrough ? nil : kind.entryPhrase
        }
    }

    /// What kind of place this is, when the writer said so directly.
    var kind: PlaceKind? {
        switch self {
        case .venue: nil
        case .kind(let kind): kind
        }
    }

    /// Maps' own words for what the place is, for the venue options.
    var categoryLabel: String? {
        switch self {
        case .venue(_, let categoryLabel): categoryLabel
        case .kind(let kind): kind.isPassingThrough ? nil : kind.displayName.lowercased()
        }
    }

    var isPassingThrough: Bool {
        kind?.isPassingThrough ?? false
    }

    /// Chip label.
    var displayName: String {
        switch self {
        case .venue(let name, let categoryLabel):
            categoryLabel.map { "\(name) · \($0)" } ?? name
        case .kind(let kind):
            kind.displayName
        }
    }

    /// What typing this answer by hand would have looked like — used so the
    /// entry says what the writer chose, not just what the day stored.
    var answerText: String {
        switch self {
        case .venue(let name, let categoryLabel):
            categoryLabel.map { "\(name), the \($0)" } ?? name
        case .kind(let kind):
            kind.isPassingThrough ? "Just walking past." : "At \(kind.entryPhrase)."
        }
    }
}
