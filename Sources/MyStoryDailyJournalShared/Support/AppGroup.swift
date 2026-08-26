import Foundation

/// Shared container identifier so the main app, the widget extension, and
/// any future extension (Share Extension, App Intents for Shortcuts) read
/// and write the same SwiftData store (build spec: "App group shared
/// container so widgets, App Intents, and extensions read/write the same
/// store," §2).
enum AppGroup {
    static let identifier = "group.com.mystorydailyjournal.app"

    /// The on-disk location for the shared SwiftData store. Falls back to
    /// the default application-support location (and effectively no
    /// widget/extension sharing) if the app group container can't be
    /// resolved — e.g. entitlements not yet provisioned in a dev build —
    /// rather than crashing.
    static var storeURL: URL {
        let directoryURL: URL
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) {
            directoryURL = containerURL
        } else {
            directoryURL = URL.applicationSupportDirectory
        }

        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL.appending(path: "MyStoryDailyJournal.sqlite")
    }
}
