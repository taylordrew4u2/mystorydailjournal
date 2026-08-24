import SwiftUI
import SwiftData

/// A couple of taps: review the shared text, optionally trim it, save.
/// Always ingests as a `sharedItem` signal on today's day rather than
/// overwriting `bodyText` — the same shape M8's automated Shortcuts
/// pipeline will use (§10).
struct ShareComposeView: View {
    let initialTitle: String?
    @State var text: String
    let onSave: () -> Void
    let onCancel: () -> Void

    init(initialTitle: String?, initialText: String, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.initialTitle = initialTitle
        self._text = State(initialValue: initialText)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if let initialTitle, !initialTitle.isEmpty {
                    Text(initialTitle)
                        .font(.headline)
                        .padding(.horizontal)
                }

                TextEditor(text: $text)
                    .font(.system(.body, design: .serif))
                    .padding(.horizontal)
            }
            .padding(.top)
            .navigationTitle("Add to My Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let context = ModelContext(PersistenceController.makeContainer())
        SharedItemIngestor.ingest(title: initialTitle, text: text, sourceApp: nil, in: context)
        onSave()
    }
}
