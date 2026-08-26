import AppIntents
import SwiftData

/// The one endpoint both Shortcuts pipelines from §3 hand off to: the
/// Notes daily-pull automation and the Message communication-trigger
/// automation. `openAppWhenRun = false` so a Shortcut running this
/// completes with no app switch visible to the user — that's what makes
/// the automation feel "near-automatic" rather than a manual forward.
///
/// Shares its write path with the Share Extension (M7) via
/// `SharedItemIngestor`, so a note pulled by Shortcuts and a note pushed
/// by hand look identical in the data model (§10).
struct IngestSharedContentIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to My Story"
    static let description = IntentDescription(
        "Adds shared text — from a Notes pull or a Messages trigger — to today's journal signals."
    )
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Text")
    var text: String

    @Parameter(title: "Title")
    var itemTitle: String?

    @Parameter(title: "Source")
    var sourceApp: String?

    func perform() async throws -> some IntentResult {
        let context = ModelContext(PersistenceController.makeContainer())
        SharedItemIngestor.ingest(title: itemTitle, text: text, sourceApp: sourceApp, in: context)
        return .result()
    }
}
