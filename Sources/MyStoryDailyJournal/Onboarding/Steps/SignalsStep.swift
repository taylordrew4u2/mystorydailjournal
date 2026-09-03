import SwiftUI

/// One clear opt-in for context collection. The detailed switches remain in
/// Settings, where they are easier to understand after the user has seen the
/// app.
struct SignalsStep: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var isRequestingAccess = false
    var onComplete: () -> Void = {}

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.top, 40)

            Text("Use helpful context?")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("This helps My Story understand an active day without turning it into awkward lines like step counts.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 10) {
                disclosureRow("Uses", "Steps and workouts, calendar items, photo counts, and place-level visits.")
                disclosureRow("Keeps", "Short facts for your private diary, so missed days still make sense.")
                disclosureRow("Shares", "Nothing from this screen. You can turn each source off later.")
            }
            .padding(.horizontal, 32)
            .padding(.top, 4)

            Spacer()

            VStack(spacing: 12) {
                Button(isRequestingAccess ? "Opening permissions..." : "Turn On Context") {
                    Task {
                        await requestAccess()
                    }
                }
                .disabled(isRequestingAccess)
                .buttonStyle(.borderedProminent)

                Button("Not now") { onComplete() }
                    .disabled(isRequestingAccess)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 24)
        }
    }

    private func disclosureRow(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func requestAccess() async {
        isRequestingAccess = true

        let healthGranted = await HealthSignalProvider().requestAuthorization()
        settings.healthEnabled = healthGranted

        let calendarGranted = await CalendarSignalProvider().requestAuthorization()
        settings.calendarEnabled = calendarGranted

        let photosGranted = await PhotosSignalProvider().requestAuthorization()
        settings.photosEnabled = photosGranted

        LocationVisitMonitor.shared.requestAlwaysAuthorization()
        settings.locationEnabled = true

        isRequestingAccess = false
        onComplete()
    }
}

#Preview {
    SignalsStep()
        .environmentObject(SettingsStore())
}
