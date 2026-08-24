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
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) else {
            return URL.applicationSupportDirectory.appending(path: "MyStoryDailyJournal.sqlite")
        }
        return containerURL.appending(path: "MyStoryDailyJournal.sqlite")
    }
}
