import SwiftUI

/// Top-level gate: setup wizard first run, app lock on top of that when
/// enabled, otherwise straight into the day list/month view.
struct AppRootView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var appLock: AppLockManager

    var body: some View {
        Group {
            if !settings.wizardCompleted {
                WizardView()
            } else if appLock.isLocked {
                AppLockGateView()
            } else {
                RootView()
            }
        }
    }
}
