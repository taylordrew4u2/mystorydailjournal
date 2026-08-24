import Foundation
import FamilyControls

/// The Family Controls entitlement isn't parental-control-only — Apple's
/// current distribution request explicitly accepts a genuine personal
/// digital-wellbeing use case (§3). Requesting `.individual` authorization
/// (not `.child`) reflects that framing.
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
            try await center.requestAuthorization(for: .individual)
            isAuthorized = center.authorizationStatus == .approved
        } catch {
            isAuthorized = false
        }
    }
}
