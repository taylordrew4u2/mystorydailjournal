import Foundation

/// A tiny app-group mailbox for "an extension asked the app to do
/// something the next time it's foregrounded." Used by the Control Center
/// control's `openAppWhenRun` intent (§3, §5) to request the bare-text
/// quick-capture sheet without guessing at App Intents' exact deep-link
/// API surface — a plain flag plus the existing `scenePhase == .active`
/// handling is certain to work.
enum PendingActionStore {
    private static let key = "pendingQuickCapture"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    static func requestQuickCapture() {
        defaults.set(true, forKey: key)
    }

    /// Reads and clears the flag in one call, so a single request only
    /// ever triggers the sheet once.
    static func consumePendingQuickCapture() -> Bool {
        let value = defaults.bool(forKey: key)
        if value { defaults.removeObject(forKey: key) }
        return value
    }
}
