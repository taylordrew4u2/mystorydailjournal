import Foundation
import Combine

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

    @Published var theme: Theme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        wizardCompleted = defaults.bool(forKey: Keys.wizardCompleted)
        writingStyle = WritingStyle(rawValue: defaults.string(forKey: Keys.writingStyle) ?? "") ?? .freeform
        selectedQuestionSetID = defaults.string(forKey: Keys.questionSetID) ?? QuestionSet.simpleRecap.id
        customPrompts = defaults.stringArray(forKey: Keys.customPrompts) ?? []
        reminderMinutesSinceMidnight = defaults.object(forKey: Keys.reminderMinutes) as? Int ?? 21 * 60
        followUpIntervalMinutes = defaults.object(forKey: Keys.followUpMinutes) as? Int ?? 90
        theme = Theme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .ink
        appLockEnabled = defaults.bool(forKey: Keys.appLockEnabled)
        appLockMethod = AppLockMethod(rawValue: defaults.string(forKey: Keys.appLockMethod) ?? "") ?? .biometric
        appLockDelayMinutes = defaults.object(forKey: Keys.appLockDelay) as? Int ?? 0
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
        static let customPrompts = "settings.customPrompts"
        static let reminderMinutes = "settings.reminderMinutesSinceMidnight"
        static let followUpMinutes = "settings.followUpIntervalMinutes"
        static let theme = "settings.theme"
        static let appLockEnabled = "settings.appLockEnabled"
        static let appLockMethod = "settings.appLockMethod"
        static let appLockDelay = "settings.appLockDelayMinutes"
    }
}
