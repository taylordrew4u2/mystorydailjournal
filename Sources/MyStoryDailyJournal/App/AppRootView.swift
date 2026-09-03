import SwiftUI

/// Top-level gate: setup wizard first run, app lock on top of that when
/// enabled, otherwise straight into the day list/month view.
struct AppRootView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var appLock: AppLockManager
    @State private var isShowingSplash = true

    var body: some View {
        ZStack {
            Group {
                if !settings.wizardCompleted {
                    WizardView()
                } else if appLock.isLocked {
                    AppLockGateView()
                } else {
                    RootView()
                }
            }

            if isShowingSplash {
                SplashView()
                    .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 0.25)) {
                isShowingSplash = false
            }
        }
    }
}

private struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "book.closed")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)

                VStack(spacing: 6) {
                    Text("My Story")
                        .font(.title.weight(.semibold))
                    Text("Loading your journal")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ProgressView()
                    .padding(.top, 4)
            }
        }
    }
}
