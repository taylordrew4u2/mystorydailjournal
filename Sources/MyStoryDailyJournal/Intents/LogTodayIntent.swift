import AppIntents
import SwiftData

/// "Log my day" exposed to Siri and assignable to the Action Button (§5
/// item 3). `entryText` has no default value, so when this runs without one
/// already supplied — a bare Siri invocation, or the Action Button with no
/// pre-filled Shortcut parameter — the system prompts for it itself before
/// `perform()` runs; that prompt is voice-first on Siri, so this can be a
/// fully hands-free, phone-in-pocket capture path.
struct LogTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Log My Day"
    static let description = IntentDescription(
        "Add a line to today's journal entry, right from Siri or the Action Button."
    )
    static let openAppWhenRun: Bool = false

    @Parameter(title: "What happened today")
    var entryText: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$entryText) to today's journal")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(PersistenceController.makeContainer())
        DayRecordRepository.appendQuickReply(entryText, on: Date(), in: context)
        NotificationManager.cancelPendingRemindersForToday()
        return .result(dialog: "Logged.")
    }
}
