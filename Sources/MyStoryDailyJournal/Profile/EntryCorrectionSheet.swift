import SwiftUI
import SwiftData

/// "What did it get wrong?" — the other half of the regenerate button.
///
/// Rewriting a day without being told why the last attempt failed produces
/// another attempt just as likely to fail. This asks, remembers the answer,
/// and then rewrites with it in hand.
struct EntryCorrectionSheet: View {
    let record: DayRecord
    /// Called once the correction is stored, so the caller can rebuild the
    /// day with it applied.
    var onSubmit: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""

    /// Starting points, because "what's wrong with this?" is a hard
    /// question cold. Each one is a real correction the app can act on.
    private let examples = [
        "It got someone's name or who they are wrong",
        "It named a place wrong",
        "It made the day sound more eventful than it was",
        "The tone isn't how I'd put it",
        "It mentioned something I don't want in my journal",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "What did it get wrong?",
                        text: $text,
                        axis: .vertical
                    )
                    .lineLimit(3...8)
                } footer: {
                    Text("Written in your own words. The app keeps this and follows it on every entry from now on — you can read and delete it under Settings › What this app knows about you.")
                }

                Section("Or start from one of these") {
                    ForEach(examples, id: \.self) { example in
                        Button(example) {
                            text = text.isEmpty ? example : text
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("What's wrong with it?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fix and remember") { submit() }
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func submit() {
        EntryCorrection.record(text, on: record.date, in: context)
        dismiss()
        onSubmit()
    }
}
