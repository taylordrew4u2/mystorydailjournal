import SwiftUI

struct AppLockGateView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var appLock: AppLockManager

    @State private var enteredCode = ""
    @State private var showCodeEntry = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)

            Text("Locked")
                .font(.title2)

            if showCodeEntry || !settings.appLockMethod.usesBiometric {
                SecureField("Passcode", text: $enteredCode)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 200)
                    .onSubmit { attemptCodeUnlock() }

                Button("Unlock") { attemptCodeUnlock() }
            }

            if settings.appLockMethod.usesBiometric {
                Button("Use Face ID") {
                    Task { await attemptBiometricUnlock() }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .task {
            if settings.appLockMethod.usesBiometric {
                await attemptBiometricUnlock()
            }
        }
    }

    private func attemptBiometricUnlock() async {
        let success = await appLock.unlockWithBiometrics()
        if !success {
            showCodeEntry = settings.appLockMethod.usesCustomCode
        }
    }

    private func attemptCodeUnlock() {
        if appLock.unlockWithCode(enteredCode) {
            errorMessage = nil
        } else {
            errorMessage = "That code didn't match."
        }
        enteredCode = ""
    }
}
