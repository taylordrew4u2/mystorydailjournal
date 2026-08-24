import SwiftUI

struct ReminderTimeStep: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var showCustomPicker = false

    private let morning = 8 * 60
    private let evening = 21 * 60

    var body: some View {
        VStack(spacing: 20) {
            Text("When should the daily reminder come?")
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.top, 40)

            VStack(spacing: 12) {
                quickPick("Morning", minutes: morning)
                quickPick("Evening", minutes: evening)

                Button {
                    showCustomPicker.toggle()
                } label: {
                    HStack {
                        Text("Custom")
                        Spacer()
                        if showCustomPicker {
                            Image(systemName: "chevron.up")
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                if showCustomPicker {
                    DatePicker("Time", selection: customTimeBinding, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func quickPick(_ title: String, minutes: Int) -> some View {
        Button {
            settings.reminderMinutesSinceMidnight = minutes
            showCustomPicker = false
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

    private var customTimeBinding: Binding<Date> {
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
            }
        )
    }
}
