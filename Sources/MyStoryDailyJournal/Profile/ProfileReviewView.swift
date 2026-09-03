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

    @Query(sort: [SortDescriptor(\Person.name)])
    private var people: [Person]

    @State private var isConfirmingForget = false
    @State private var isRelearning = false

    var body: some View {
        List {
            Section {
                Toggle("Keep learning about me", isOn: $settings.profileLearningEnabled)
                Text("""
                The app reads your own entries — names you mention, the \
                places you name, when you write, the words you use — and \
                keeps what it notices so your entries sound like you and \
                know who you mean. All of it happens on this phone.
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section {
                if people.isEmpty {
                    Text("No names saved yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(people) { person in
                        NavigationLink {
                            PersonRelationshipEditView(person: person)
                        } label: {
                            personRow(person)
                        }
                    }
                }
            } header: {
                Text("People")
            } footer: {
                Text("Relationships are private writing context. They are not shown as diary tags.")
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

    private func personRow(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(person.name)
                .font(.body)
            Text(person.descriptionForWriting ?? "Relationship not set")
                .font(.caption)
                .foregroundStyle(.secondary)
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

private struct PersonRelationshipEditView: View {
    @Bindable var person: Person
    @Environment(\.modelContext) private var context

    var body: some View {
        Form {
            Section {
                Text(person.name)
                    .font(.title3.weight(.semibold))
                Text("Tell the diary who this is so future entries use the right context.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Relationship") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RelationshipPrompter.commonRelationships, id: \.self) { option in
                            Button {
                                person.relationship = option
                                person.askedAt = .now
                                try? context.save()
                            } label: {
                                Text(option)
                                    .font(.footnote.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        person.relationship == option
                                            ? Color.accentColor
                                            : Color.secondary.opacity(0.12)
                                    )
                                    .foregroundStyle(
                                        person.relationship == option
                                            ? Color(uiColor: .systemBackground)
                                            : Color.primary
                                    )
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                TextField("Relationship", text: stringBinding(\.relationship))
            }

            Section {
                TextField("What they go by, or pronouns", text: stringBinding(\.pronouns))
                TextField("Private note", text: stringBinding(\.note), axis: .vertical)
                    .lineLimit(2...5)
            } footer: {
                Text("Used only to make private entries read more accurately.")
            }
        }
        .navigationTitle("Person")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stringBinding(_ keyPath: ReferenceWritableKeyPath<Person, String?>) -> Binding<String> {
        Binding(
            get: { person[keyPath: keyPath] ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                person[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed
                person.askedAt = .now
                try? context.save()
            }
        )
    }
}
