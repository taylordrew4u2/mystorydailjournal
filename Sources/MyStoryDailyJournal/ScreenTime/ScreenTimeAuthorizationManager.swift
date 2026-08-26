import Foundation
import FamilyControls

/// The Family Controls entitlement isn't parental-control-only — Apple's
/// current distribution request explicitly accepts a genuine personal
/// digital-wellbeing use case (§3). Requesting `.individual` authorization
/// (not `.child`) reflects that framing.
///
/// **Version-sensitive** (§18): the exact wording Apple expects in a Family
/// Controls entitlement distribution request — and whether `.individual`
/// personal-use requests are still accepted on the same terms — has shifted
/// between releases; confirm current requirements before submitting for
/// review.
@MainActor
final class ScreenTimeAuthorizationManager: ObservableObject {
    static let shared = ScreenTimeAuthorizationManager()

    @Published private(set) var isAuthorized: Bool

    private let center = AuthorizationCenter.shared

    init() {
        isAuthorized = center.authorizationStatus == .approved
    }

    func requestAuthorization() async {
        do {
            try await Self.requestSystemAuthorization()
            isAuthorized = center.authorizationStatus == .approved
        } catch {
            isAuthorized = false
        }
    }

    /// AuthorizationCenter isn't Sendable, so the async request runs in a
    /// nonisolated context instead of sending the instance off the main actor.
    private nonisolated static func requestSystemAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }
}
