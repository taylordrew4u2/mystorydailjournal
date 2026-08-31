import Foundation
import SwiftData

/// What a fact is about, which decides when it's worth telling the writer's
/// story with.
enum ProfileFactKind: String, Codable, Sendable, CaseIterable {
    /// Someone who appears in this life — how often, alongside whom, where.
    case person
    /// A place that recurs: home, work, the gym, the usual café.
    case place
    /// A pattern in time: when they write, which evenings they're out.
    case rhythm
    /// What their journal keeps coming back to.
    case theme
    /// How they write — length, sentences, whether they use contractions.
    case voice

    var displayName: String {
        switch self {
        case .person: "People"
        case .place: "Places"
        case .rhythm: "Rhythms"
        case .theme: "Themes"
        case .voice: "Voice"
        }
    }
}

/// One thing the app has learned about the person, kept rather than
/// recomputed on the spot — so the picture deepens as the journal grows
/// instead of resetting to whatever the last month happened to contain.
///
/// Every fact is derived on-device from the writer's own journal, carries
/// how many days it was seen on, and is individually reviewable, mutable
/// and deletable (`ProfileReviewView`). Nothing here is inferred about
/// anyone but the writer, and nothing leaves the device — it syncs only to
/// their own private iCloud, like the rest of the store (§11, §12).
///
/// CloudKit schema rules apply as everywhere else: defaults on every
/// property, no unique constraints (identity is enforced in
/// `ProfileLearner` by kind + subject).
@Model
final class ProfileFact {
    var id: UUID = UUID()
    var kindRaw: String = ProfileFactKind.theme.rawValue

    /// What the fact is about — a person's name, a place, a theme. The
    /// identity half of "kind + subject", which is how the learner knows
    /// whether it's updating a fact or adding one.
    var subject: String = ""

    /// The learned detail, already phrased so it can drop straight into a
    /// prompt: "usually at the gym on Tuesday and Thursday evenings."
    var detail: String = ""

    /// How many days this was observed on — the app's confidence in it, and
    /// how facts are ranked when the brief has to fit a budget.
    var observationCount: Int = 0

    var firstObserved: Date = Date.distantPast
    var lastObserved: Date = Date.distantPast

    /// The writer's own overrides. A pinned fact is always offered to the
    /// writing; a muted one never is, and the learner leaves it muted no
    /// matter how often it sees it again.
    var isPinned: Bool = false
    var isMuted: Bool = false

    var kind: ProfileFactKind {
        get { ProfileFactKind(rawValue: kindRaw) ?? .theme }
        set { kindRaw = newValue.rawValue }
    }

    init(
        kind: ProfileFactKind,
        subject: String,
        detail: String,
        observationCount: Int = 1,
        firstObserved: Date = .now,
        lastObserved: Date = .now
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.subject = subject
        self.detail = detail
        self.observationCount = observationCount
        self.firstObserved = firstObserved
        self.lastObserved = lastObserved
    }

    /// How the fact reads in a profile brief.
    var sentence: String {
        detail.isEmpty ? subject : detail
    }
}
