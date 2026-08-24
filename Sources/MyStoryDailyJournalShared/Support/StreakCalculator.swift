import Foundation

/// §8: "Streak logic counts both user entries and auto-digests as
/// 'covered,' but tracks a separate 'written' count. Do not shame the user
/// for auto days." `currentStreak` is every consecutive covered day working
/// back from today (a `.blank` day breaks it); `writtenCount` is how many of
/// those same days the user actually wrote themselves — a quieter, purely
/// informational number, never framed as a target or a failure.
enum StreakCalculator {
    struct Stats: Equatable {
        var currentStreak: Int
        var writtenCount: Int
    }

    static func stats(for days: [DayRecord], asOf today: Date = .now, calendar: Calendar = .current) -> Stats {
        let byDay = Dictionary(days.map { (DateUtilities.startOfDay(for: $0.date, calendar: calendar), $0) }, uniquingKeysWith: { first, _ in first })

        var streak = 0
        var written = 0
        var cursor = DateUtilities.startOfDay(for: today, calendar: calendar)

        while let day = byDay[cursor], day.source != .blank {
            streak += 1
            if day.isUserWritten {
                written += 1
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return Stats(currentStreak: streak, writtenCount: written)
    }
}
