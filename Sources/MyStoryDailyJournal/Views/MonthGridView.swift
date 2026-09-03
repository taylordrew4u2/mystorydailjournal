import SwiftUI
import SwiftData

/// Calendar-style month grid. Each date cell tints at low opacity when that
/// day is covered (written or auto-generated), neutral otherwise (§16).
struct MonthGridView: View {
    @Query private var days: [DayRecord]
    @Environment(\.modelContext) private var context
    @State private var monthAnchor: Date = DateUtilities.startOfDay(for: .now)
    @State private var quickTodayText = ""

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { shiftMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(monthAnchor, format: .dateTime.month(.wide).year())
                    .font(.headline)
                Spacer()
                Button { shiftMonth(by: 1) } label: { Image(systemName: "chevron.right") }
            }
            .padding(.horizontal)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(daysInMonth(), id: \.self) { date in
                    NavigationLink(value: date) {
                        DayCell(date: date, isCovered: coveredDates.contains(date))
                    }
                }
            }
            .padding(.horizontal)

            QuickTodayWriteView(text: $quickTodayText) {
                saveQuickToday()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
    }

    private var coveredDates: Set<Date> {
        Set(days.map { DateUtilities.startOfDay(for: $0.date) })
    }

    private func daysInMonth() -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: monthAnchor) else { return [] }
        var result: [Date] = []
        var current = interval.start
        while current < interval.end {
            result.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return result
    }

    private func shiftMonth(by value: Int) {
        if let newAnchor = calendar.date(byAdding: .month, value: value, to: monthAnchor) {
            monthAnchor = newAnchor
        }
    }

    private func saveQuickToday() {
        DayRecordRepository.appendQuickReply(quickTodayText, on: .now, in: context)
        quickTodayText = ""
        NotificationManager.cancelPendingRemindersForToday()
        LiveActivityManager.refreshForToday(isJournaled: true)
    }
}

private struct DayCell: View {
    let date: Date
    let isCovered: Bool

    var body: some View {
        Text(date, format: .dateTime.day())
            .font(.footnote)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(isCovered ? Color.accentColor.opacity(0.18) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(.primary)
    }
}

private struct QuickTodayWriteView: View {
    @Binding var text: String
    let onSave: () -> Void

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("Write a quick note", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            HStack {
                Spacer()
                Button("Save") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedText.isEmpty)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
