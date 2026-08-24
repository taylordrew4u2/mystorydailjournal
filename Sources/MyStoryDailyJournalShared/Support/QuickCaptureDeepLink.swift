import Foundation

/// The custom URL the "Write today" widget uses to open the app straight
/// into the bare-text-field quick-capture surface (§5 item 2). Lives in
/// Shared so the widget extension and the host app agree on the exact same
/// literal instead of each hardcoding their own copy of the scheme/host.
enum QuickCaptureDeepLink {
    static let url = URL(string: "mystory://quick-capture")!
}
