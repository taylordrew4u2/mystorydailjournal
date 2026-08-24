import Foundation
import Combine

/// Flips on when the bare-text-field quick capture surface should present —
/// from the toolbar button, from the widget's deep link URL, or from the
/// "Log my day" App Intent when it has no dictated text to attach directly.
@MainActor
final class QuickCaptureCoordinator: ObservableObject {
    @Published var isPresented = false

    func handle(url: URL) {
        guard url.scheme == QuickCaptureDeepLink.url.scheme,
              url.host == QuickCaptureDeepLink.url.host else { return }
        isPresented = true
    }
}
