import Foundation
import UserNotifications
import SwiftData

/// Handles notification delivery and responses, including the
/// `UNTextInputNotificationAction` quick reply — the single most important
/// interaction in the app (build spec §0, §5.1). This runs regardless of
/// whether the app is foregrounded, backgrounded, or not running at all;
/// iOS launches the process briefly, headless, to run this delegate.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let container: ModelContainer
    private let settings: SettingsStore

    init(container: ModelContainer, settings: SettingsStore) {
        self.container = container
        self.settings = settings
    }

    /// Show the banner even while the app is in the foreground, since the
    /// quick-reply flow should behave identically either way.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.identifier.hasPrefix(NotificationManager.reminderRequestIDPrefix) {
            let settings = settings
            Task { @MainActor in
                NotificationManager.scheduleFollowUp(minutesFromNow: settings.followUpIntervalMinutes)
            }
        }
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard response.actionIdentifier == NotificationManager.quickReplyActionID,
              let textResponse = response as? UNTextInputNotificationResponse else {
            return
        }

        let context = ModelContext(container)
        DayRecordRepository.appendQuickReply(textResponse.userText, on: .now, in: context)
        NotificationManager.cancelPendingRemindersForToday()
        Task { @MainActor in
            LiveActivityManager.refreshForToday(isJournaled: true)
        }
    }
}
