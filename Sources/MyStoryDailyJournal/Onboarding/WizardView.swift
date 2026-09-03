import SwiftUI

/// First-run setup (§7). The wizard can be completed by accepting sensible
/// defaults (freeform, generated diary on, no signals, no lock, ink
/// palette), with no screen showing more than two action buttons.
///
/// M1 shipped steps 1-3 and 6-8 (welcome, writing style, reminder time,
/// palette, app lock offer, done). M3 added step 4 (signals); M8 adds
/// step 5 (automations), and generated diary mode is offered up front so
/// the user can keep automatic writing on or choose facts-only from day one.
struct WizardView: View {
    private enum Step: Int, CaseIterable {
        case welcome, writingStyle, generatedDiary, reminderTime, signals, automations, palette, appLock, done
    }

    @EnvironmentObject private var settings: SettingsStore
    @State private var step: Step = .welcome

    var body: some View {
        VStack(spacing: 0) {
            ProgressBar(current: step.rawValue, total: Step.allCases.count)
                .padding()

            Group {
                switch step {
                case .welcome:
                    WelcomeStep()
                case .writingStyle:
                    WritingStyleStep()
                case .generatedDiary:
                    GeneratedDiaryStep()
                case .reminderTime:
                    ReminderTimeStep()
                case .signals:
                    SignalsStep(onComplete: { move(1) })
                case .automations:
                    AutomationsStep()
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
            // navigation so the screen never shows competing setup actions.
            EmptyView()
        } else if step != .done {
            HStack {
                if step != .welcome {
                    Button("Back") { move(-1) }
                }
                Spacer()
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

private struct GeneratedDiaryStep: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: settings.generatedDiaryEnabled ? "text.book.closed" : "list.bullet.clipboard")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.top, 36)

            Text("What should unwritten days show?")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Write plain diary drafts", isOn: $settings.generatedDiaryEnabled)

                Text(settings.generatedDiaryEnabled
                     ? "If you forget to write, My Story can turn collected facts into a simple diary draft you can edit."
                     : "If you forget to write, My Story will show the collected facts instead of writing for you.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            if settings.generatedDiaryEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Smooth drafts on device", isOn: $settings.digestRewriteEnabled)
                    Text("Optional. Uses the on-device language model when available. The plain version is always kept as the fallback.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
            }

            Spacer()
        }
    }
}
