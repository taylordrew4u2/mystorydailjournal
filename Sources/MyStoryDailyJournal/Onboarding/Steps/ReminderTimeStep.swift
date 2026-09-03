import SwiftUI

struct ReminderTimeStep: View {
    @EnvironmentObject private var settings: SettingsStore

    private let morning = 8 * 60
    private let evening = 21 * 60

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.top, 40)

            VStack(spacing: 8) {
                Text("Daily reminder")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("Pick the time that is easiest to answer. You can change the exact time later in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                quickPick("Morning", minutes: morning)
                quickPick("Evening", minutes: evening)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func quickPick(_ title: String, minutes: Int) -> some View {
        Button {
            settings.reminderMinutesSinceMidnight = minutes
        } label: {
            HStack {
                Text(title)
                Spacer()
                if settings.reminderMinutesSinceMidnight == minutes {
                    Image(systemName: "checkmark")
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}
