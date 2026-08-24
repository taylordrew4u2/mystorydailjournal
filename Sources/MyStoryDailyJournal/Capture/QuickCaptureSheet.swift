import SwiftUI
import SwiftData

/// The "bare text field" fast-capture surface (§5 item 2): opened from a
/// widget tap or the Action Button/Siri intent, with nothing on screen but
/// a text field, a mic button for voice capture, and Save/Cancel. No
/// placeholder copy, no prior screens to click through (§6's "no pressure
/// UI" rule applies here too).
struct QuickCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @StateObject private var recorder = VoiceRecorder()

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextEditor(text: $text)
                    .font(.system(.body, design: .serif))
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .padding(.horizontal)

                MicButton(recorder: recorder, text: $text)
                    .padding(.bottom, 8)
            }
            .padding(.top)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear { isFocused = true }
    }

    private func save() {
        DayRecordRepository.appendQuickReply(text, on: .now, in: context)
        NotificationManager.cancelPendingRemindersForToday()
        dismiss()
    }
}
