import SwiftUI
import SwiftData

/// Calendar-style month grid. Each date cell tints at low opacity when that
/// day is covered (written or auto-generated), neutral otherwise (§16).
struct MonthGridView: View {
    @Query private var days: [DayRecord]
    @State private var monthAnchor: Date = DateUtilities.startOfDay(for: .now)

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

            Spacer()
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
