import SwiftUI

struct DoneStep: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("You're set up")
                .font(.title2.weight(.semibold))
            Text("Today's entry is waiting whenever you're ready.")
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
            Spacer()
        }
        .task {
            if await NotificationManager.requestAuthorization() {
                NotificationManager.scheduleDailyReminder(settings: settings)
            }
        }
    }
}
