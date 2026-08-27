import SwiftUI
import SwiftData

/// One-tap tokens that constitute a valid entry by themselves (§5 item 4).
/// No text entry required — tapping a chip immediately logs it via
/// `TagLogger`, the same path the Lock Screen widget's intent uses.
struct TagChipRow: View {
    let date: Date
    @Environment(\.modelContext) private var context
    @Query private var days: [DayRecord]

    private var todayRecord: DayRecord? {
        days.first { DateUtilities.startOfDay(for: $0.date) == DateUtilities.startOfDay(for: date) }
    }

    private var activeTagNames: Set<String> {
        Set(todayRecord?.tags?.map(\.name) ?? [])
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PresetTag.allCases) { tag in
                    chip(for: tag)
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip(for tag: PresetTag) -> some View {
        let isActive = activeTagNames.contains(tag.rawValue)
        return Button {
            TagLogger.logTag(named: tag.rawValue, on: date, in: context)
        } label: {
            Text(tag.rawValue)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isActive ? Color.accentColor : Color.secondary.opacity(0.12))
                .foregroundStyle(isActive ? Color(uiColor: .systemBackground) : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
