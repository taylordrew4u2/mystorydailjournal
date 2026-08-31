import SwiftUI
import SwiftData

/// The questions behind the floating pen: who the people in this journal
/// actually are.
///
/// One person at a time, most-present first, every field optional and
/// skippable. Answering once changes every entry that mentions them from
/// then on — "Dana" stops being a name the app is repeating back and
/// becomes the writer's sister.
struct RelationshipSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [Person] = []
    @State private var index = 0
    @State private var relationship = ""
    @State private var pronouns = ""
    @State private var note = ""
    @State private var describedCount = 0

    private var person: Person? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if let person {
                    questions(for: person)
                } else {
                    finished
                }
            }
            .navigationTitle("People in your story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if person != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(relationship.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .task { load() }
    }

    private func questions(for person: Person) -> some View {
        Form {
            Section {
                Text("Who is \(person.name) to you?")
                    .font(.title3)
                Text("\(dayCount(for: person)) days in your journal mention them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RelationshipPrompter.commonRelationships, id: \.self) { option in
                            Button {
                                relationship = option
                            } label: {
                                Text(option)
                                    .font(.footnote.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        relationship == option
                                            ? Color.accentColor
                                            : Color.secondary.opacity(0.12)
                                    )
                                    .foregroundStyle(
                                        relationship == option
                                            ? Color(uiColor: .systemBackground)
                                            : Color.primary
                                    )
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                TextField("Or say it your own way", text: $relationship)
            }

            Section {
                TextField("What they go by, or their pronouns", text: $pronouns)
                TextField("Anything else worth knowing", text: $note, axis: .vertical)
                    .lineLimit(2...4)
            } footer: {
                Text("All optional. This is only used to write your entries the way you'd write them, and never leaves your phone.")
            }

            Section {
                Button("Skip \(person.name) for now") { skip() }
            }
        }
    }

    private var finished: some View {
        ContentUnavailableView {
            Label(
                describedCount > 0 ? "That's everyone" : "No one to ask about yet",
                systemImage: describedCount > 0 ? "checkmark.circle" : "person.2"
            )
        } description: {
            Text(
                describedCount > 0
                    ? "Your entries will know who they are from now on."
                    : "Tag someone on a day and the pen will ask who they are."
            )
        }
    }

    private func dayCount(for person: Person) -> Int {
        (person.dayRecords ?? []).count
    }

    private func load() {
        guard queue.isEmpty else { return }
        queue = RelationshipPrompter.peopleToAskAbout(in: context)
    }

    private func save() {
        guard let person else { return }
        RelationshipPrompter.describe(
            person,
            relationship: relationship,
            pronouns: pronouns,
            note: note,
            in: context
        )
        describedCount += 1
        advance()
    }

    private func skip() {
        guard let person else { return }
        RelationshipPrompter.skip(person, in: context)
        advance()
    }

    private func advance() {
        relationship = ""
        pronouns = ""
        note = ""
        index += 1
    }
}

/// The pen itself: always there, bottom-right, with a dot when the app has
/// someone it would like to understand better.
struct FloatingPenButton: View {
    @Environment(\.modelContext) private var context
    @State private var isPresented = false
    @State private var hasQuestions = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "pencil.and.scribble")
                .font(.title2)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .frame(width: 56, height: 56)
                .background(Color.accentColor, in: Circle())
                .overlay(alignment: .topTrailing) {
                    if hasQuestions {
                        Circle()
                            .fill(.red)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(Color(uiColor: .systemBackground), lineWidth: 2))
                    }
                }
                .shadow(radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tell the app about the people in your journal")
        .padding(20)
        .sheet(isPresented: $isPresented, onDismiss: refresh) {
            RelationshipSheet()
        }
        .task { refresh() }
    }

    private func refresh() {
        hasQuestions = RelationshipPrompter.hasQuestions(in: context)
    }
}
