import SwiftUI

/// §7 step 4: each signal gets its own plain-language screen before the
/// system permission prompt fires — never all four prompts back to back
/// with no context. A small stepper of its own, nested inside the wizard's
/// step, one signal at a time; skippable individually or as a whole.
struct SignalsStep: View {
    private struct SignalInfo {
        let title: String
        let benefit: String
        let systemImage: String
        let disclosure: DataSourceDisclosure
        let onEnable: () async -> Void
    }

    @EnvironmentObject private var settings: SettingsStore
    @State private var index = 0
    var onComplete: () -> Void = {}

    private var signals: [SignalInfo] {
        [
            SignalInfo(
                title: "Steps and workouts",
                benefit: "A quiet, low-effort signal for days you don't write — how much you moved, and any workouts logged.",
                systemImage: "figure.walk",
                disclosure: .health,
                onEnable: {
                    let granted = await HealthSignalProvider().requestAuthorization()
                    if granted { settings.healthEnabled = true }
                }
            ),
            SignalInfo(
                title: "Calendar events",
                benefit: "Events you actually attended help fill in an auto-generated day, and can suggest who you were with.",
                systemImage: "calendar",
                disclosure: .calendar,
                onEnable: {
                    let granted = await CalendarSignalProvider().requestAuthorization()
                    settings.calendarEnabled = granted
                }
            ),
            SignalInfo(
                title: "Photos",
                benefit: "How many photos you took (and whether any were screenshots) says a lot about a day, without reading their content.",
                systemImage: "photo",
                disclosure: .photos,
                onEnable: {
                    let granted = await PhotosSignalProvider().requestAuthorization()
                    settings.photosEnabled = granted
                }
            ),
            SignalInfo(
                title: "Places visited",
                benefit: "Place-level visits — not a continuous track — for days you didn't write anything yourself.",
                systemImage: "location",
                disclosure: .location,
                onEnable: {
                    LocationVisitMonitor.shared.requestAlwaysAuthorization()
                    settings.locationEnabled = true
                }
            ),
        ]
    }

    var body: some View {
        VStack(spacing: 20) {
            let signal = signals[index]

            Text("\(index + 1) of \(signals.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 24)

            Image(systemName: signal.systemImage)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)

            Text(signal.title)
                .font(.title3.weight(.semibold))

            Text(signal.benefit)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // The full terms, on screen before any system prompt: exactly
            // what's read, what's kept, what ever leaves the phone, and why
            // (§12). "I Agree" is the only path to the OS permission.
            VStack(alignment: .leading, spacing: 10) {
                disclosureRow("What it reads", signal.disclosure.reads)
                disclosureRow("What it keeps", signal.disclosure.keeps)
                disclosureRow("What leaves your phone", signal.disclosure.leavesPhone)
            }
            .padding(.horizontal, 32)
            .padding(.top, 4)

            Spacer()

            VStack(spacing: 12) {
                Button("I Agree — Turn On") {
                    Task {
                        await signal.onEnable()
                        advance()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Not now") { advance() }
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

    private func advance() {
        if index < signals.count - 1 {
            index += 1
        } else {
            onComplete()
        }
    }
}
