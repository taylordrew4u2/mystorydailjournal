import Foundation
import BackgroundTasks
import SwiftData

/// Drives `DigestEngine` from two triggers, per §3's "background execution
/// is not guaranteed": a `BGAppRefreshTask` around local midnight, and a
/// foreground catch-up on every launch/foreground so a missed refresh
/// window never loses a day (§14 acceptance criteria).
enum DigestScheduler {
    static let taskIdentifier = "com.mystorydailyjournal.app.digest-refresh"

    static func register(container: ModelContainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask, container: container)
        }
    }

    static func scheduleNextMidnightRun() {
        let calendar = Calendar.current
        let today = DateUtilities.startOfDay(for: .now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
              let fireDate = calendar.date(byAdding: .minute, value: 5, to: tomorrow) else {
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = fireDate
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Called on every launch/foreground — the reliable half of the pair,
    /// since `BGAppRefreshTask` runs at the system's discretion (§3).
    static func runForegroundCatchUp(container: ModelContainer) {
        Task {
            let context = ModelContext(container)
            await DigestEngine.catchUpMissingDays(in: context)
            await WatchedFolderManager.shared.checkForNewFiles(in: context)
        }
    }

    private static func handle(_ task: BGAppRefreshTask, container: ModelContainer) {
        scheduleNextMidnightRun()

        let work = Task {
            let context = ModelContext(container)
            await DigestEngine.catchUpMissingDays(in: context)
            await WatchedFolderManager.shared.checkForNewFiles(in: context)
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            work.cancel()
        }
    }
}
