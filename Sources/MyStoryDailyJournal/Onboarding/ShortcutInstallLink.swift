import Foundation
import UIKit

/// A pre-built automation the app can offer to install (§3, §7 step 5):
/// a Notes daily-pull, or a Messages per-sender trigger. Both hand their
/// result to `IngestSharedContentIntent`.
///
/// The real, shipped mechanism is an "Install automation" button that
/// opens Shortcuts pre-filled via a `.shortcut` link (a signed file
/// exported from the Shortcuts app and hosted somewhere reachable — an
/// app-bundled resource or a small CDN). That file isn't something this
/// codebase can produce on its own; a `.shortcut` is a binary plist built
/// and signed inside the Shortcuts app itself, not hand-authorable as
/// source. `installURL` is `nil` until a real one is exported and added
/// here — until then, the button opens the Shortcuts app itself and the UI
/// copy explains what to build by hand, so the feature degrades to a
/// slightly worse but still-functional path rather than a dead button.
struct ShortcutTemplate {
    let name: String
    let summary: String
    let manualSteps: [String]
    let installURL: URL?

    static let notesDailyPull = ShortcutTemplate(
        name: "Pull today's Notes",
        summary: "Runs once a day and hands anything you wrote in Notes today to My Story.",
        manualSteps: [
            "Add a Time of Day personal automation, set to run once daily.",
            "Add the \"Find Notes\" action, filtered to Created Today (optionally scoped to a folder, e.g. \"Journal\").",
            "Add the \"Add to My Story\" action and pass the found notes' text to it.",
            "Turn off \"Ask Before Running\" so it runs unattended.",
        ],
        installURL: nil
    )

    static let messageTrigger = ShortcutTemplate(
        name: "Log messages from someone",
        summary: "Runs the moment a message arrives from senders you pick, and logs it immediately.",
        manualSteps: [
            "Add a Message personal automation, and pick specific senders — not \"any message.\"",
            "Set it to Run Immediately, with \"Ask Before Running\" off.",
            "Add the \"Add to My Story\" action and pass the incoming message's text to it.",
        ],
        installURL: nil
    )

    /// Opens the pre-filled `.shortcut` link if one's been added, or just
    /// the Shortcuts app itself as a fallback.
    func open() {
        let url = installURL ?? URL(string: "shortcuts://")!
        UIApplication.shared.open(url)
    }
}
