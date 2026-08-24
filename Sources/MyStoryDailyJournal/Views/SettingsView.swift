import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Section("Writing") {
                Picker("Default style", selection: $settings.writingStyle) {
                    ForEach(WritingStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
            }

            Section("Reminder") {
                DatePicker(
                    "Time",
                    selection: reminderTimeBinding,
                    displayedComponents: .hourAndMinute
                )
                Stepper(
                    "Follow-up after \(settings.followUpIntervalMinutes) min",
                    value: $settings.followUpIntervalMinutes,
                    in: 15...240,
                    step: 15
                )
            }

            Section("Appearance") {
                Picker("Palette", selection: $settings.theme) {
                    ForEach(Theme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
            }

            Section("Privacy") {
                Toggle("App lock", isOn: $settings.appLockEnabled)
                if settings.appLockEnabled {
                    Picker("Method", selection: $settings.appLockMethod) {
                        Text("Face ID / Touch ID").tag(AppLockMethod.biometric)
                        Text("Passcode").tag(AppLockMethod.customCode)
                        Text("Both").tag(AppLockMethod.both)
                    }
                }
                NavigationLink("Your Data") {
                    YourDataView()
                }
            }

            Section {
                Button("Redo setup") {
                    settings.wizardCompleted = false
                }
            }
        }
        .navigationTitle("Settings")
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = settings.reminderMinutesSinceMidnight / 60
                components.minute = settings.reminderMinutesSinceMidnight % 60
                return Calendar.current.date(from: components) ?? .now
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                settings.reminderMinutesSinceMidnight = (components.hour ?? 21) * 60 + (components.minute ?? 0)
                NotificationManager.scheduleDailyReminder(settings: settings)
            }
        )
    }
}

/// Required, plainly-worded in-app content, not a link to a PDF (§12).
struct YourDataView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("""
                Everything you write stays on your device and, if you turn on \
                iCloud, in your own private iCloud account. Nothing is sent \
                to the developer or any other company.

                There is no analytics software in this app and no advertising \
                software. Nothing about your use of the app is tracked.

                If you install the optional Notes or Messages automations, \
                those run entirely inside your own Shortcuts app. Turning an \
                automation off or deleting it in Shortcuts stops it \
                immediately — nothing keeps running on this app's side.
                """)
                .font(.body)
            }
            .padding()
        }
        .navigationTitle("Your Data")
    }
}
