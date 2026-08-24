import Foundation
import SwiftData

/// The document-picker-once, security-scoped-bookmark-forever pattern from
/// §3: "the user grants one folder once ... the app keeps a security-scoped
/// bookmark, and watches that folder for new files each day." This is the
/// real, permanent answer for "files created" — not a device-wide watcher,
/// which no sandboxed app can build.
@MainActor
final class WatchedFolderManager: ObservableObject {
    static let shared = WatchedFolderManager()

    @Published private(set) var folderDisplayName: String?

    private let defaults = UserDefaults.standard
    private let bookmarkKey = "watchedFolder.bookmark"
    private let knownFilesKey = "watchedFolder.knownFileNames"

    init() {
        folderDisplayName = resolveURL()?.lastPathComponent
    }

    /// Called with the URL `.fileImporter` hands back — that closure is the
    /// only window in which the URL's security scope is guaranteed valid,
    /// so the bookmark has to be created right here, synchronously.
    func grantAccess(to url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return
        }
        defaults.set(bookmark, forKey: bookmarkKey)
        defaults.removeObject(forKey: knownFilesKey)
        folderDisplayName = url.lastPathComponent
    }

    func stopWatching() {
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: knownFilesKey)
        folderDisplayName = nil
    }

    /// Diffs the folder's current contents against what was seen at the
    /// last check, recording any new file names as `.fileWatch` signals on
    /// today. Called from the same foreground-catch-up / midnight paths
    /// `DigestEngine` uses (§4). A file that never leaves another app's own
    /// sandbox stays invisible — nothing here claims otherwise.
    func checkForNewFiles(in context: ModelContext) {
        guard let url = resolveURL() else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let currentNames = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        let knownNames = Set(defaults.stringArray(forKey: knownFilesKey) ?? [])
        let newNames = Set(currentNames).subtracting(knownNames)

        defaults.set(currentNames, forKey: knownFilesKey)
        guard !newNames.isEmpty else { return }

        let record = DayRecordRepository.record(for: .now, in: context)
        for name in newNames.sorted() {
            let payload = FileWatchPayload(fileName: name, folderName: url.lastPathComponent)
            let signal = DaySignal(kind: .fileWatch, timestamp: .now)
            signal.setPayload(payload)
            signal.dayRecord = record
            context.insert(signal)
        }
        try? context.save()
    }

    private func resolveURL() -> URL? {
        guard let bookmarkData = defaults.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return url
    }
}
