import Foundation
import Combine
import UIKit

/// Local, device-specific preferences (build spec §7: "these are local
/// preferences, not part of the CloudKit-synced DayRecord store"). Backed by
/// `UserDefaults.standard` for now; will move to an app-group suite once a
/// widget or extension needs to read these values (M2+).
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults: UserDefaults

    @Published var wizardCompleted: Bool {
        didSet { defaults.set(wizardCompleted, forKey: Keys.wizardCompleted) }
    }

    /// Transient, in-memory only: tells `RootView` to land straight on
    /// today's entry the moment the wizard finishes (§7 step 8).
    @Published var justCompletedWizard = false

    @Published var writingStyle: WritingStyle {
        didSet { defaults.set(writingStyle.rawValue, forKey: Keys.writingStyle) }
    }

    @Published var selectedQuestionSetID: String {
        didSet { defaults.set(selectedQuestionSetID, forKey: Keys.questionSetID) }
    }

    /// The voice the on-device model writes in (digest rewrites and
    /// guided-answer weaving). Default `.natural` changes nothing.
    @Published var writingTone: WritingTone {
        didSet { defaults.set(writingTone.rawValue, forKey: Keys.writingTone) }
    }

    @Published var customPrompts: [String] {
        didSet { defaults.set(customPrompts, forKey: Keys.customPrompts) }
    }

    /// Minutes since local midnight for the daily reminder. Default 21:00.
    @Published var reminderMinutesSinceMidnight: Int {
        didSet { defaults.set(reminderMinutesSinceMidnight, forKey: Keys.reminderMinutes) }
    }

    @Published var followUpIntervalMinutes: Int {
        didSet { defaults.set(followUpIntervalMinutes, forKey: Keys.followUpMinutes) }
    }

    /// §17 acceptance criteria: "Switching palette presets updates the
    /// in-app tint and the home screen icon together." `didSet` doesn't
    /// fire for the assignment inside `init` (Swift property-observer
    /// semantics), only for later changes — which is exactly right here,
    /// since `setAlternateIconName` shouldn't be called before the app has
    /// finished launching.
    @Published var theme: Theme {
        didSet {
            defaults.set(theme.rawValue, forKey: Keys.theme)
            UIApplication.shared.setAlternateIconName(theme.alternateIconName)
        }
    }

    @Published var appLockEnabled: Bool {
        didSet { defaults.set(appLockEnabled, forKey: Keys.appLockEnabled) }
    }

    @Published var appLockMethod: AppLockMethod {
        didSet { defaults.set(appLockMethod.rawValue, forKey: Keys.appLockMethod) }
    }

    @Published var appLockDelayMinutes: Int {
        didSet { defaults.set(appLockDelayMinutes, forKey: Keys.appLockDelay) }
    }

    /// Per-signal opt-in toggles (§12: "Every signal individually
    /// disableable"). HealthKit exposes no readable authorization status
    /// for read-only access, so `healthEnabled` doubles as this app's own
    /// record of "the user granted this" — set only after a successful
    /// `requestAuthorization` call, never assumed.
    @Published var healthEnabled: Bool {
        didSet { defaults.set(healthEnabled, forKey: Keys.healthEnabled) }
    }

    @Published var calendarEnabled: Bool {
        didSet { defaults.set(calendarEnabled, forKey: Keys.calendarEnabled) }
    }

    @Published var photosEnabled: Bool {
        didSet { defaults.set(photosEnabled, forKey: Keys.photosEnabled) }
    }

    @Published var mediaEnabled: Bool {
        didSet { defaults.set(mediaEnabled, forKey: Keys.mediaEnabled) }
    }

    @Published var locationEnabled: Bool {
        didSet { defaults.set(locationEnabled, forKey: Keys.locationEnabled) }
    }

    /// Separate from `locationEnabled` per §12: full street-level accuracy
    /// is a second, explicit ask on top of place-level Always authorization.
    @Published var fullAccuracyLocationEnabled: Bool {
        didSet { defaults.set(fullAccuracyLocationEnabled, forKey: Keys.fullAccuracyLocation) }
    }

    /// The last day `DigestEngine.catchUpMissingDays` checked through
    /// (inclusive). `nil` means "never run" — the engine backfills from
    /// yesterday in that case, not from the beginning of time.
    @Published var lastDigestCheckDate: Date? {
        didSet {
            if let lastDigestCheckDate {
                defaults.set(lastDigestCheckDate, forKey: Keys.lastDigestCheckDate)
            } else {
                defaults.removeObject(forKey: Keys.lastDigestCheckDate)
            }
        }
    }

    /// One-shot: whether the post-install historical backfill has already
    /// reconstructed the days before installation from Health/Calendar/Photos
    /// history. Stays `false` until at least one signal source is enabled, so
    /// enabling a source later still triggers the backfill.
    @Published var historyBackfillCompleted: Bool {
        didSet { defaults.set(historyBackfillCompleted, forKey: Keys.historyBackfillCompleted) }
    }

    /// §9, §13 M10: optional on-device rewrite of the digest into a more
    /// natural voice. Default off — the rule-based composer stays the
    /// fallback regardless.
    @Published var digestRewriteEnabled: Bool {
        didSet { defaults.set(digestRewriteEnabled, forKey: Keys.digestRewriteEnabled) }
    }

    /// Whether the app keeps a standing picture of the writer — the people,
    /// places, rhythms, themes and voice it has learned from their own
    /// journal (`ProfileLearner`). On by default: the app has always read
    /// recent entries to write in their voice, and this is that, remembered.
    /// Turning it off stops new learning; what's already known is reviewed
    /// and deleted in "What this app knows about you."
    @Published var profileLearningEnabled: Bool {
        didSet { defaults.set(profileLearningEnabled, forKey: Keys.profileLearning) }
    }

    /// Optional links the writer gives directly to their own public
    /// profiles. Stored as links only; any future reader of those pages has
    /// to be an explicit, user-started import path.
    @Published var socialProfileLinks: [String] {
        didSet { defaults.set(socialProfileLinks, forKey: Keys.socialProfileLinks) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        wizardCompleted = defaults.bool(forKey: Keys.wizardCompleted)
        writingStyle = WritingStyle(rawValue: defaults.string(forKey: Keys.writingStyle) ?? "") ?? .freeform
        selectedQuestionSetID = defaults.string(forKey: Keys.questionSetID) ?? QuestionSet.simpleRecap.id
        writingTone = WritingTone(rawValue: defaults.string(forKey: Keys.writingTone) ?? "") ?? .natural
        customPrompts = defaults.stringArray(forKey: Keys.customPrompts) ?? []
        reminderMinutesSinceMidnight = defaults.object(forKey: Keys.reminderMinutes) as? Int ?? 21 * 60
        followUpIntervalMinutes = defaults.object(forKey: Keys.followUpMinutes) as? Int ?? 90
        theme = Theme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .ink
        appLockEnabled = defaults.bool(forKey: Keys.appLockEnabled)
        appLockMethod = AppLockMethod(rawValue: defaults.string(forKey: Keys.appLockMethod) ?? "") ?? .biometric
        appLockDelayMinutes = defaults.object(forKey: Keys.appLockDelay) as? Int ?? 0
        healthEnabled = defaults.bool(forKey: Keys.healthEnabled)
        calendarEnabled = defaults.bool(forKey: Keys.calendarEnabled)
        photosEnabled = defaults.bool(forKey: Keys.photosEnabled)
        mediaEnabled = defaults.bool(forKey: Keys.mediaEnabled)
        locationEnabled = defaults.bool(forKey: Keys.locationEnabled)
        fullAccuracyLocationEnabled = defaults.bool(forKey: Keys.fullAccuracyLocation)
        lastDigestCheckDate = defaults.object(forKey: Keys.lastDigestCheckDate) as? Date
        historyBackfillCompleted = defaults.bool(forKey: Keys.historyBackfillCompleted)
        digestRewriteEnabled = defaults.bool(forKey: Keys.digestRewriteEnabled)
        profileLearningEnabled = defaults.object(forKey: Keys.profileLearning) as? Bool ?? true
        socialProfileLinks = defaults.stringArray(forKey: Keys.socialProfileLinks) ?? []
    }

    /// The active question set for guided entries: a starter set, or the
    /// user's custom prompts if they wrote their own.
    var activeQuestionSet: QuestionSet {
        if selectedQuestionSetID == "custom", customPrompts.count >= 3 {
            return QuestionSet(id: "custom", name: "Custom", prompts: customPrompts)
        }
        return QuestionSet.starterSets.first { $0.id == selectedQuestionSetID } ?? .simpleRecap
    }

    private enum Keys {
        static let wizardCompleted = "settings.wizardCompleted"
        static let writingStyle = "settings.writingStyle"
        static let questionSetID = "settings.questionSetID"
        static let writingTone = "settings.writingTone"
        static let customPrompts = "settings.customPrompts"
        static let reminderMinutes = "settings.reminderMinutesSinceMidnight"
        static let followUpMinutes = "settings.followUpIntervalMinutes"
        static let theme = "settings.theme"
        static let appLockEnabled = "settings.appLockEnabled"
        static let appLockMethod = "settings.appLockMethod"
        static let appLockDelay = "settings.appLockDelayMinutes"
        static let healthEnabled = "settings.healthEnabled"
        static let calendarEnabled = "settings.calendarEnabled"
        static let photosEnabled = "settings.photosEnabled"
        static let mediaEnabled = "settings.mediaEnabled"
        static let locationEnabled = "settings.locationEnabled"
        static let fullAccuracyLocation = "settings.fullAccuracyLocationEnabled"
        static let lastDigestCheckDate = "settings.lastDigestCheckDate"
        static let historyBackfillCompleted = "settings.historyBackfillCompleted"
        static let digestRewriteEnabled = "settings.digestRewriteEnabled"
        /// Shared with `ProfileLearner`, which runs off the main actor and
        /// reads this key directly.
        static let profileLearning = ProfileLearner.learningEnabledKey
        static let socialProfileLinks = "settings.socialProfileLinks"
    }
}
