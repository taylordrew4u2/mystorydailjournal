import Foundation
import UIKit

/// A pre-built automation the app can offer to install (§3, §7 step 5):
/// a Notes daily-pull that hands its result to `IngestSharedContentIntent`.
/// (A Messages per-sender trigger existed here too, but was cut — not
/// worth its setup burden.)
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
        summary: "Runs once a day, all by itself, and adds anything you wrote in Apple Notes that day to My Story.",
        manualSteps: [
            "Open the Shortcuts app. (Can't find it? Swipe down on your home screen and type Shortcuts.)",
            "Tap Automation at the bottom of the screen, then tap + in the top corner.",
            "Tap Time of Day. Set it to Daily, pick a time like 9:00 PM, select Run Immediately, and tap Next.",
            "Tap New Blank Automation, then tap Add Action.",
            "Search for Find Notes and tap it. Then tap Add Filter inside it and set: Created Date → is → Today.",
            "Tap Add Action again, search for My Story, and tap Add to My Story.",
            "Inside Add to My Story, tap the light-blue text field and pick Notes — that connects the notes it found to your journal.",
            "Tap Done. That's everything — from now on it runs every day without you touching it.",
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
