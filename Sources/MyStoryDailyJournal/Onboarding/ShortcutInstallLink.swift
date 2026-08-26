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
///
/// **Version-sensitive** (§18): the exact `"Find Notes"`/`"Open Note"`
/// action names, their available filter options, and how reliably a
/// personal automation with "Ask Before Running" off actually runs
/// unattended have all changed across Shortcuts/iOS releases — confirm the
/// manual steps above still match the current Shortcuts app before
/// shipping this copy. Separately, `open()` always leaves this app's
/// foreground state (§18) — there's no way to install or run a Shortcuts
/// automation without switching apps, so anything depending on this path
/// resuming afterward must not assume immediate re-foregrounding.
struct ShortcutTemplate {
    let name: String
    let summary: String
    let manualSteps: [String]
    let installURL: URL?

    static let notesDailyPull = ShortcutTemplate(
        name: "Pull today's Notes",
        summary: "Runs once a day and hands anything you wrote in Notes today to My Story.",
        manualSteps: [
            "Open the Shortcuts app (already on your iPhone — swipe down on the home screen and type \"Shortcuts\" if you can't find it).",
            "Tap \"Automation\" in the bar at the bottom of the screen, then tap the + in the top-right corner.",
            "Tap \"Time of Day.\" Pick a time (9:00 PM works well), make sure \"Daily\" is selected, choose \"Run Immediately,\" then tap \"Next.\"",
            "Tap \"New Blank Automation,\" then \"Add Action.\" Type \"Find Notes\" in the search box and tap it in the results.",
            "In the Find Notes box, tap \"Add Filter\" and set it to Created Date → is today.",
            "Tap the search bar again, type \"My Story,\" and tap \"Add to My Story.\" Tap the pale text bubble inside it and choose the \"Notes\" variable, so the notes it found are what get logged.",
            "Tap \"Done\" in the top corner. You're finished — it now runs by itself every day.",
        ],
        installURL: nil
    )

    static let messageTrigger = ShortcutTemplate(
        name: "Log messages from someone",
        summary: "Runs the moment a message arrives from senders you pick, and logs it immediately.",
        manualSteps: [
            "Open the Shortcuts app (already on your iPhone — swipe down on the home screen and type \"Shortcuts\" if you can't find it).",
            "Tap \"Automation\" in the bar at the bottom of the screen, then tap the + in the top-right corner.",
            "Tap \"Message.\" Next to \"Sender,\" tap \"Choose\" and pick the specific people whose messages you want journaled (don't leave it as any message).",
            "Choose \"Run Immediately,\" then tap \"Next.\"",
            "Tap \"New Blank Automation,\" then \"Add Action.\" Type \"My Story\" in the search box and tap \"Add to My Story.\"",
            "Tap the pale text bubble inside it and choose \"Shortcut Input,\" so the incoming message's text is what gets logged.",
            "Tap \"Done\" in the top corner. From now on, messages from those people are logged the moment they arrive.",
        ],
        installURL: nil
    )

    /// The numbered steps as one plain-text block — copied to the clipboard
    /// before Shortcuts opens, because opening Shortcuts leaves this app
    /// (§18) and takes these instructions off the screen with it.
    var stepsText: String {
        let numbered = manualSteps.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        return "\(name) — setup steps:\n\(numbered)"
    }

    /// Opens the pre-filled `.shortcut` link if one's been added, or just
    /// the Shortcuts app itself as a fallback.
    @MainActor func open() {
        let url = installURL ?? URL(string: "shortcuts://")!
        UIApplication.shared.open(url)
    }
}
