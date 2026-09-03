import SwiftUI

/// First-run setup keeps only the decisions needed to start journaling.
/// Deeper personalization stays in Settings so setup does not feel like a
/// checklist before the user has even seen the diary.
struct WizardView: View {
    private enum Step: Int, CaseIterable {
        case welcome, diaryMode, signals, reminderTime, done
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
                case .diaryMode:
                    DiaryModeStep()
                case .signals:
                    SignalsStep(onComplete: { move(1) })
                case .reminderTime:
                    ReminderTimeStep()
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
            // SignalsStep owns its two choices because one path may request
            // system permissions before continuing.
            EmptyView()
        } else if step != .done {
            HStack {
                if step != .welcome {
                    Button("Back") { move(-1) }
                }
                Spacer()
                Button("Next") { move(1) }
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

private struct DiaryModeStep: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: settings.generatedDiaryEnabled ? "text.book.closed" : "list.bullet.clipboard")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.top, 36)

            Text("How should the diary work?")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 16) {
                Picker("When you write", selection: $settings.writingStyle) {
                    ForEach(WritingStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                Toggle("Create diary drafts", isOn: $settings.generatedDiaryEnabled)

                Text(settings.generatedDiaryEnabled
                     ? "If you forget to write, My Story can make a plain draft from the facts it collected."
                     : "If you turn this off, My Story only shows the facts it collected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if settings.generatedDiaryEnabled {
                    Toggle("Smooth drafts on device", isOn: $settings.digestRewriteEnabled)
                    Text("Optional. Keeps the draft human and plain when the on-device model is available.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }
}
