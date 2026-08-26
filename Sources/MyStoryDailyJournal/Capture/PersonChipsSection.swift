import SwiftUI
import SwiftData

/// People metadata for one day (§3, §16): tagged people, a one-tap recent
/// list, a free-text "add someone new," and calendar-attendee suggestions
/// that only ever become fact once the user taps to accept them — never
/// written automatically.
struct PersonChipsSection: View {
    let record: DayRecord

    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.modelContext) private var context
    @StateObject private var nearbyPeople = NearbyPeopleService.shared
    @State private var newName = ""
    @State private var isAddingPerson = false

    private var taggedPeople: [Person] {
        record.people ?? []
    }

    private var recentPeople: [Person] {
        PeopleRepository.recentPeople(in: context)
            .filter { candidate in !taggedPeople.contains { $0.id == candidate.id } }
    }

    private var attendeeSuggestions: [String] {
        let taggedNames = Set(taggedPeople.map { $0.name.lowercased() })
        let names = (record.signals ?? [])
            .filter { $0.kind == .calendar }
            .compactMap { $0.payload(as: CalendarPayload.self) }
            .flatMap(\.attendeeNames)
        return Array(Set(names)).filter { !taggedNames.contains($0.lowercased()) }.sorted()
    }

    private var nearbySuggestions: [String] {
        let taggedNames = Set(taggedPeople.map { $0.name.lowercased() })
        return nearbyPeople.nearbySuggestions.filter { !taggedNames.contains($0.lowercased()) }
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

            if !attendeeSuggestions.isEmpty {
                row(title: "From your calendar", chips: attendeeSuggestions.map { name in
                    Chip(label: name, isFilled: false, isSuggestion: true) {
                        let person = PeopleRepository.findOrCreatePerson(named: name, in: context)
                        PeopleRepository.toggle(person, on: record, in: context)
                    }
                })
            }

            if settings.nearbyPeopleEnabled, !nearbySuggestions.isEmpty {
                row(title: "Nearby", chips: nearbySuggestions.map { name in
                    Chip(label: name, isFilled: false, isSuggestion: true) {
                        let person = PeopleRepository.findOrCreatePerson(named: name, in: context)
                        PeopleRepository.toggle(person, on: record, in: context)
                        nearbyPeople.dismissSuggestion(name)
                    }
                })
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
    var isSuggestion: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isFilled ? Color.accentColor : Color.secondary.opacity(isSuggestion ? 0.08 : 0.12))
                .foregroundStyle(isFilled ? Color.white : Color.primary)
                .overlay {
                    if isSuggestion {
                        Capsule().strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3]))
                    }
                }
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
