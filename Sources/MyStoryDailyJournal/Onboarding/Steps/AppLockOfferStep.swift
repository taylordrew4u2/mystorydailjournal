import SwiftUI

private enum CodeEntryStage {
    case entering
    case confirming
    case saved
}

/// Offered once, here. Off by default even if this step is skipped or the
/// toggle is left unset — no nagging to enable it later (§7, §12).
struct AppLockOfferStep: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var codeInput = ""
    @State private var firstCode = ""
    @State private var stage: CodeEntryStage = .entering
    @State private var showMismatch = false

    private let codeLength = 4

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "faceid")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.top, 32)

            Text("Lock the app?")
                .font(.title3)

            Text("Optional. You can turn this on or off any time in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Toggle("Require Face ID or a code to open the app", isOn: $settings.appLockEnabled)
                .padding(.horizontal, 24)

            if settings.appLockEnabled {
                Picker("Method", selection: $settings.appLockMethod) {
                    Text("Face ID / Touch ID").tag(AppLockMethod.biometric)
                    Text("Passcode").tag(AppLockMethod.customCode)
                    Text("Both").tag(AppLockMethod.both)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)

                if settings.appLockMethod.usesCustomCode {
                    VStack(spacing: 8) {
                        if stage == .saved {
                            Label("Code saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        } else {
                            SecureField(stage == .confirming ? "Re-enter the code" : "Set a \(codeLength)-digit code", text: $codeInput)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                                .onChange(of: codeInput) { _, newValue in
                                    handleCodeInputChange(newValue)
                                }
                            if showMismatch {
                                Text("Those codes didn't match. Try again.")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }

            Spacer()
        }
    }

    /// Digit-only, capped at `codeLength`, and requires typing the same
    /// code twice before it's ever written to the keychain — a typo the
    /// user doesn't notice would otherwise silently become their permanent
    /// unlock code with no way to know it's wrong until they're locked out.
    private func handleCodeInputChange(_ newValue: String) {
        let digitsOnly = String(newValue.filter(\.isNumber).prefix(codeLength))
        if digitsOnly != newValue {
            codeInput = digitsOnly
            return
        }

        guard digitsOnly.count == codeLength else { return }

        switch stage {
        case .entering:
            firstCode = digitsOnly
            stage = .confirming
            showMismatch = false
            codeInput = ""
        case .confirming:
            if digitsOnly == firstCode {
                KeychainStore.saveCode(digitsOnly)
                stage = .saved
                showMismatch = false
            } else {
                showMismatch = true
                stage = .entering
                firstCode = ""
                codeInput = ""
            }
        case .saved:
            break
        }
    }
}
