import SwiftUI

/// Offered once, here. Off by default even if this step is skipped or the
/// toggle is left unset — no nagging to enable it later (§7, §12).
struct AppLockOfferStep: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var customCode = ""

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
                    SecureField("Set a code", text: $customCode)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .padding(.horizontal, 24)
                        .onChange(of: customCode) { _, newValue in
                            if newValue.count >= 4 {
                                KeychainStore.saveCode(newValue)
                            }
                        }
                }
            }

            Spacer()
        }
    }
}
