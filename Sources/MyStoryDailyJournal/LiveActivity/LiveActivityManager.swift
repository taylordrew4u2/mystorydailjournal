import Foundation
import ActivityKit

/// Owns the app's one daily Live Activity (§3, §5 item 2). Live Activities
/// are time-boxed by the system, so this restarts one every time it's
/// asked to refresh if the previous one has already ended — "restarted
/// daily" in practice means "refreshed opportunistically whenever the app
/// is foregrounded or an entry is saved," since there's no guaranteed
/// background moment to do it at exactly midnight (§3).
///
/// Known gap: a tag logged from the Lock Screen widget (M2) doesn't refresh
/// this until the app is next foregrounded, since that intent runs in the
/// widget extension process and this manager is only driven from the app.
///
/// **Version-sensitive** (§18): iOS enforces its own maximum Live Activity
/// lifetime (system-set, not app-configurable, and it has moved across
/// releases) — confirm the current limit against the actual SDK, since a
/// "restarted daily" activity that the system ends early mid-day needs the
/// same opportunistic-refresh handling as any other stale one.
@MainActor
enum LiveActivityManager {
    static func refreshForToday(isJournaled: Bool) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let dateDescription = Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        let state = JournalActivityAttributes.ContentState(isJournaled: isJournaled, dateDescription: dateDescription)

        if let existing = Activity<JournalActivityAttributes>.activities.first {
            Task { await existing.update(ActivityContent(state: state, staleDate: nil)) }
            return
        }

        do {
            _ = try Activity.request(
                attributes: JournalActivityAttributes(),
                content: ActivityContent(state: state, staleDate: nil)
            )
        } catch {
            // Live Activities are a nice-to-have surface, not a data path —
            // failing to start one should never interrupt the rest of the app.
        }
    }

    static func endAll() {
        for activity in Activity<JournalActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
