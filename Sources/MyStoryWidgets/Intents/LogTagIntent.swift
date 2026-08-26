import AppIntents
import SwiftData

/// Performed directly from the Lock Screen widget's button tap. Deliberately
/// `openAppWhenRun = false` — the whole point of this capture surface is
/// that it never launches the app, matching the notification quick-reply's
/// "no app launch" behavior (§0, §5 item 2).
struct LogTagIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Tag"
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Tag")
    var tag: PresetTag

    init() {
        tag = .good
    }

    init(tag: PresetTag) {
        self.tag = tag
    }

    func perform() async throws -> some IntentResult {
        let context = ModelContext(PersistenceController.makeContainer())
        TagLogger.logTag(named: tag.rawValue, on: Date(), in: context)
        return .result()
    }
}
