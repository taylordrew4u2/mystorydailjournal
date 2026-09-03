import SwiftUI
import SwiftData

/// People metadata for one day. This only shows people already attached to
/// the record; the diary screen does not prompt the writer to add anyone.
struct PersonChipsSection: View {
    let record: DayRecord

    @Environment(\.modelContext) private var context

    private var taggedPeople: [Person] {
        record.people ?? []
    }

    var body: some View {
        if !taggedPeople.isEmpty {
            row(title: "People mentioned", chips: taggedPeople.map { person in
                Chip(label: person.name, isFilled: true) {
                    PeopleRepository.toggle(person, on: record, in: context)
                }
            })
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
