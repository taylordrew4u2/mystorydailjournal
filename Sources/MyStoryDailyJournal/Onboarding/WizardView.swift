import SwiftUI

/// First-run setup (§7). Never a gate: every step is skippable, and the
/// wizard can be exited at any point with the app left fully usable on
/// sensible defaults (freeform, no signals, no lock, ink palette).
///
/// M1 shipped steps 1-3 and 6-8 (welcome, writing style, reminder time,
/// palette, app lock offer, done). M3 adds step 4 (signals); step 5
/// (automations) still lands in M8.
struct WizardView: View {
    private enum Step: Int, CaseIterable {
        case welcome, writingStyle, reminderTime, signals, palette, appLock, done
    }

    @EnvironmentObject private var settings: SettingsStore
    @State private var step: Step = .welcome

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if step != .done {
                    Button("Exit setup") { settings.wizardCompleted = true }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ProgressBar(current: step.rawValue, total: Step.allCases.count)
                .padding()

            Group {
                switch step {
                case .welcome:
                    WelcomeStep()
                case .writingStyle:
                    WritingStyleStep()
                case .reminderTime:
                    ReminderTimeStep()
                case .signals:
                    SignalsStep(onComplete: { move(1) })
                case .palette:
                    PaletteStep()
                case .appLock:
                    AppLockOfferStep()
                case .done:
                    DoneStep()
                }
            }
            .frame(maxHeight: .infinity)

            bottomBar
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var bottomBar: some View {
        if step == .signals {
            // SignalsStep drives its own per-signal Turn On/Not now
            // navigation; only offer a way to skip the whole step here.
            HStack {
                Button("Back") { move(-1) }
                Spacer()
                Button("Skip all") { move(1) }
                    .foregroundStyle(.secondary)
            }
            .padding()
        } else if step != .done {
            HStack {
                if step != .welcome {
                    Button("Back") { move(-1) }
                }
                Spacer()
                Button("Skip") { move(1) }
                    .foregroundStyle(.secondary)
                Button(step == .appLock ? "Continue" : "Next") { move(1) }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        } else {
            Button("Start journaling") {
                settings.justCompletedWizard = true
                settings.wizardCompleted = true
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    private func move(_ delta: Int) {
        let newRaw = step.rawValue + delta
        guard let newStep = Step(rawValue: newRaw) else {
            settings.wizardCompleted = true
            return
        }
        step = newStep
    }
}

private struct ProgressBar: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(height: 4)
            }
        }
    }
}
