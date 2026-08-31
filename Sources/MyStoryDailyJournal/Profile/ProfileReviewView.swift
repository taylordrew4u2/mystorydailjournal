import SwiftUI
import SwiftData

/// Everything the app has worked out about the writer, in plain sentences,
/// with a delete button on every one of them.
///
/// A journal that learns about you owes you the ability to read what it
/// thinks it knows and to take any of it away. Nothing here is a black box:
/// each fact says how many days it rests on, when it was last true, and can
/// be pinned (always used), muted (never used), or deleted outright.
struct ProfileReviewView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\ProfileFact.observationCount, order: .reverse)])
    private var facts: [ProfileFact]

    @State private var isConfirmingForget = false
    @State private var isRelearning = false

    var body: some View {
        List {
            Section {
                Toggle("Keep learning about me", isOn: $settings.profileLearningEnabled)
                Text("""
                The app reads your own entries — the people you tag, the \
                places you name, when you write, the words you use — and \
                keeps what it notices so your entries sound like you and \
                know who you mean. All of it happens on this phone.
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if facts.isEmpty {
                Section {
                    Text("Nothing learned yet. Write a few days and this fills in.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(ProfileFactKind.allCases, id: \.self) { kind in
                let group = facts.filter { $0.kind == kind }
                if !group.isEmpty {
                    Section(kind.displayName) {
                        ForEach(group) { fact in
                            row(for: fact)
                        }
                        .onDelete { offsets in
                            delete(offsets.map { group[$0] })
                        }
                    }
                }
            }

            Section {
                Button {
                    relearn()
                } label: {
                    if isRelearning {
                        ProgressView()
                    } else {
                        Text("Re-read my journal now")
                    }
                }
                .disabled(isRelearning)

                Button("Forget everything about me", role: .destructive) {
                    isConfirmingForget = true
                }
            } footer: {
                Text("Forgetting clears only what the app concluded. Your entries are untouched.")
            }
        }
        .navigationTitle("What this app knows")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Forget everything about you?",
            isPresented: $isConfirmingForget,
            titleVisibility: .visible
        ) {
            Button("Forget it all", role: .destructive) {
                ProfileLearner.forgetEverything(in: context)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every person, place, rhythm, theme and note about your voice is deleted. Your journal stays exactly as it is, and the app will start learning again from it unless you turn learning off.")
        }
    }

    private func row(for fact: ProfileFact) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fact.sentence)
                .font(.body)
                .foregroundStyle(fact.isMuted ? .secondary : .primary)
            HStack(spacing: 6) {
                Text("seen on \(fact.observationCount) days")
                if fact.isPinned { Label("Always used", systemImage: "pin.fill") }
                if fact.isMuted { Label("Never used", systemImage: "speaker.slash") }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .swipeActions(edge: .leading) {
            Button {
                fact.isPinned.toggle()
                if fact.isPinned { fact.isMuted = false }
                try? context.save()
            } label: {
                Label(fact.isPinned ? "Unpin" : "Pin", systemImage: "pin")
            }
            .tint(.accentColor)

            Button {
                fact.isMuted.toggle()
                if fact.isMuted { fact.isPinned = false }
                try? context.save()
            } label: {
                Label(fact.isMuted ? "Use" : "Mute", systemImage: "speaker.slash")
            }
            .tint(.gray)
        }
    }

    private func delete(_ facts: [ProfileFact]) {
        for fact in facts {
            context.delete(fact)
        }
        try? context.save()
    }

    /// A fresh pass over the journal, on demand — for when the writer has
    /// just deleted a fact and wants to see what the app makes of things
    /// now, or has turned learning back on.
    private func relearn() {
        isRelearning = true
        Task {
            ProfileLearner.learn(in: context)
            isRelearning = false
        }
    }
}
