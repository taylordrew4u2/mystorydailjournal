import Foundation
import LocalAuthentication
import Combine

/// Gates the app on foreground per `SettingsStore.appLockEnabled`. Off by
/// default; never prompted on first run unless the user opts in during
/// onboarding or later in Settings (build spec §12).
@MainActor
final class AppLockManager: ObservableObject {
    @Published private(set) var isLocked: Bool = false

    private let settings: SettingsStore
    private var backgroundedAt: Date?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// Call when the scene enters the background.
    func sceneDidEnterBackground() {
        guard settings.appLockEnabled else { return }
        backgroundedAt = .now
    }

    /// Call when the scene becomes active again. Locks immediately unless
    /// the user's configured grace delay hasn't elapsed yet.
    func sceneDidBecomeActive() {
        guard settings.appLockEnabled, let backgroundedAt else { return }
        let elapsedMinutes = Date.now.timeIntervalSince(backgroundedAt) / 60
        if elapsedMinutes >= Double(settings.appLockDelayMinutes) {
            isLocked = true
        }
        self.backgroundedAt = nil
    }

    func unlockWithBiometrics() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock your journal"
            )
            if success { isLocked = false }
            return success
        } catch {
            return false
        }
    }

    func unlockWithCode(_ code: String) -> Bool {
        guard let stored = KeychainStore.loadCode(), stored == code else { return false }
        isLocked = false
        return true
    }
}
