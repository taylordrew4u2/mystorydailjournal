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
    private var today: Date { DateUtilities.startOfDay(for: .now) }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { shiftMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(monthAnchor, format: .dateTime.month(.wide).year())
                    .font(.title3.weight(.semibold))
                Spacer()
                Button { shiftMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Next month")
            }
            .padding(.horizontal)
            .padding(.top, 8)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(calendarCells().enumerated()), id: \.offset) { _, date in
                    if let date {
                        NavigationLink(value: date) {
                            DayCell(
                                date: date,
                                isCovered: coveredDates.contains(date),
                                isToday: date == today
                            )
                        }
                    } else {
                        Color.clear
                            .frame(minHeight: 40)
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

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
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

    private func calendarCells() -> [Date?] {
        guard let firstDate = daysInMonth().first else { return [] }
        let weekday = calendar.component(.weekday, from: firstDate)
        let leadingBlanks = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leadingBlanks) + daysInMonth().map(Optional.some)
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
    let isToday: Bool

    var body: some View {
        Text(date, format: .dateTime.day())
            .font(.footnote.weight(isToday ? .semibold : .regular))
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(isCovered ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.05))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isToday ? Color.accentColor : Color.clear, lineWidth: 1.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Add one quick detail.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            TextField("What should this day remember?", text: $text, axis: .vertical)
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
