import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// The Share Extension's entry point (§3, §4: "a Share Extension so the
/// user can push a specific note into the journal in a couple of taps, any
/// time" — the dependable path, not just a convenience layer, since
/// `Find Notes`/`Open Note` in Shortcuts have had real per-release
/// reliability regressions per §3).
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await loadSharedContentAndPresent() }
    }

    private func loadSharedContentAndPresent() async {
        let (title, text) = await Self.extractSharedContent(from: extensionContext)

        let composeView = ShareComposeView(
            initialTitle: title,
            initialText: text,
            onSave: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            },
            onCancel: { [weak self] in
                let error = NSError(domain: "com.mystorydailyjournal.app.share", code: 0)
                self?.extensionContext?.cancelRequest(withError: error)
            }
        )

        let hosting = UIHostingController(rootView: composeView)
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }

    private static func extractSharedContent(from context: NSExtensionContext?) async -> (title: String?, text: String) {
        guard let item = context?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else {
            return (nil, "")
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            let text = (try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)) as? String
            return (item.attributedTitle?.string, text ?? "")
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            let url = (try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier)) as? URL
            return (item.attributedTitle?.string, url?.absoluteString ?? "")
        }
        return (item.attributedTitle?.string, item.attributedContentText?.string ?? "")
    }
}
