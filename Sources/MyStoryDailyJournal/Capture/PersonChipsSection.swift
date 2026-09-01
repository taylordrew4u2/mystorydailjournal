import SwiftUI
import SwiftData

/// People metadata for one day (§3, §16): tagged people, a one-tap recent
/// list, and a free-text "add someone new." Calendar guest lists are not
/// mined for people; the writer has to name or tag someone directly.
struct PersonChipsSection: View {
    let record: DayRecord

    @Environment(\.modelContext) private var context
    @State private var newName = ""
    @State private var isAddingPerson = false

    private var taggedPeople: [Person] {
        record.people ?? []
    }

    private var recentPeople: [Person] {
        PeopleRepository.recentPeople(in: context)
            .filter { candidate in !taggedPeople.contains { $0.id == candidate.id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !taggedPeople.isEmpty {
                row(title: "With", chips: taggedPeople.map { person in
                    Chip(label: person.name, isFilled: true) {
                        PeopleRepository.toggle(person, on: record, in: context)
                    }
                })
            }

            if !recentPeople.isEmpty || isAddingPerson {
                row(title: "Add someone", chips: recentPeople.map { person in
                    Chip(label: person.name, isFilled: false) {
                        PeopleRepository.toggle(person, on: record, in: context)
                    }
                } + [addChip])
            } else {
                row(title: "Add someone", chips: [addChip])
            }

            if isAddingPerson {
                HStack {
                    TextField("Name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        let person = PeopleRepository.findOrCreatePerson(named: newName, in: context)
                        PeopleRepository.toggle(person, on: record, in: context)
                        newName = ""
                        isAddingPerson = false
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var addChip: Chip {
        Chip(label: "New person", isFilled: false) {
            isAddingPerson = true
        }
    }

    private func row(title: String, chips: [Chip]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips) { $0 }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct Chip: View, Identifiable {
    nonisolated var id: String { label }
    let label: String
    let isFilled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isFilled ? Color.accentColor : Color.secondary.opacity(0.12))
                .foregroundStyle(isFilled ? Color(uiColor: .systemBackground) : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
