import Foundation
@preconcurrency import UserNotifications

/// Owns notification authorization, category/action registration, and daily
/// reminder scheduling (build spec §8, §5.1).
///
/// The whole point of `UNTextInputNotificationAction` is that it answers the
/// notification without opening the app: the action below deliberately does
/// NOT include `.foreground`, so the system hands the typed text to
/// `NotificationDelegate` in the background and the banner just dismisses.
enum NotificationManager {
    static let quickReplyCategoryID = "DAILY_QUICK_REPLY"
    static let quickReplyActionID = "QUICK_REPLY_ACTION"

    static let reminderRequestIDPrefix = "daily-reminder"
    static let followUpRequestIDPrefix = "daily-followup"

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        registerCategories()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func registerCategories() {
        let quickReply = UNTextInputNotificationAction(
            identifier: quickReplyActionID,
            title: "Write",
            options: [],
            textInputButtonTitle: "Save",
            textInputPlaceholder: "Add a line about today"
        )

        let category = UNNotificationCategory(
            identifier: quickReplyCategoryID,
            actions: [quickReply],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Schedules the recurring daily reminder plus an escalation follow-up,
    /// both driven by `SettingsStore`. Call again whenever the reminder time
    /// or follow-up interval changes; old requests are replaced by ID.
    @MainActor
    static func scheduleDailyReminder(settings: SettingsStore) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [
            "\(reminderRequestIDPrefix)-recurring",
        ])

        var components = DateComponents()
        components.hour = settings.reminderMinutesSinceMidnight / 60
        components.minute = settings.reminderMinutesSinceMidnight % 60

        let content = makeContent(body: "What's the one line for today?")
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: "\(reminderRequestIDPrefix)-recurring",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    /// Schedules a one-shot escalation for today, `followUpIntervalMinutes`
    /// after the primary reminder fires. Call this from the primary
    /// reminder's delivery handling, not on a fixed calendar trigger, so it
    /// naturally never fires once the day already has an entry.
    static func scheduleFollowUp(minutesFromNow: Int) {
        let center = UNUserNotificationCenter.current()
        let identifier = "\(followUpRequestIDPrefix)-\(DateUtilities.startOfDay(for: .now).timeIntervalSince1970)"

        let content = makeContent(body: "Still time for a line about today.")
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(minutesFromNow * 60),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    /// Cancels any pending reminder/follow-up for today. Called once an
    /// entry exists (so the app "goes quiet," per §8) and, later, once the
    /// midnight digest job closes out the day.
    static func cancelPendingRemindersForToday() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let todayFollowUpID = "\(followUpRequestIDPrefix)-\(DateUtilities.startOfDay(for: .now).timeIntervalSince1970)"
            let idsToCancel = requests
                .map(\.identifier)
                .filter { $0 == todayFollowUpID }
            center.removePendingNotificationRequests(withIdentifiers: idsToCancel)
        }
    }

    private static func makeContent(body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "My Story"
        content.body = body
        content.categoryIdentifier = quickReplyCategoryID
        content.interruptionLevel = .timeSensitive
        content.sound = .default
        return content
    }
}
