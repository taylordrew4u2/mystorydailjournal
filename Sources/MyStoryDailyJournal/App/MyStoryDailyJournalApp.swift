import SwiftUI
import SwiftData
import UserNotifications

@main
struct MyStoryDailyJournalApp: App {
    let container: ModelContainer
    @StateObject private var settings: SettingsStore
    @StateObject private var appLock: AppLockManager
    @StateObject private var quickCapture = QuickCaptureCoordinator()
    @StateObject private var cloudStatus = CloudAccountStatus.shared
    private let notificationDelegate: NotificationDelegate

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container = PersistenceController.makeContainer()
        self.container = container

        let settings = SettingsStore.shared
        _settings = StateObject(wrappedValue: settings)
        _appLock = StateObject(wrappedValue: AppLockManager(settings: settings))

        notificationDelegate = NotificationDelegate(container: container, settings: settings)
        UNUserNotificationCenter.current().delegate = notificationDelegate
        NotificationManager.registerCategories()

        // Resumes visit monitoring across launches if Always authorization
        // was already granted; a no-op otherwise (§4).
        LocationVisitMonitor.shared.startMonitoringVisitsIfAuthorized()

        // Must register before the app finishes launching (§3: background
        // execution isn't guaranteed, so this is the "best effort" half —
        // the foreground catch-up below is the reliable half).
        DigestScheduler.register(container: container)

        // `onChange(of: scenePhase)` below doesn't fire for the very first
        // transition into `.active` on a cold launch, so these also need
        // to run here — the scenePhase handler covers every foreground
        // after that.
        DigestScheduler.runForegroundCatchUp(container: container)
        DigestScheduler.scheduleNextMidnightRun()
        CloudAccountStatus.shared.refresh()
        Self.refreshLiveActivity(container: container)
    }

    /// Reads today's actual state before refreshing, rather than guessing —
    /// the Live Activity's whole point is that its "journaled" flag is
    /// trustworthy at a glance.
    private static func refreshLiveActivity(container: ModelContainer) {
        let context = ModelContext(container)
        let isJournaled = DayRecordRepository.existingRecord(for: .now, in: context)?.isUserWritten ?? false
        LiveActivityManager.refreshForToday(isJournaled: isJournaled)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(settings)
                .environmentObject(appLock)
                .environmentObject(quickCapture)
                .environmentObject(cloudStatus)
                .tint(settings.theme.accent)
                .onOpenURL { url in
                    quickCapture.handle(url: url)
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                appLock.sceneDidEnterBackground()
            case .active:
                appLock.sceneDidBecomeActive()
                DigestScheduler.runForegroundCatchUp(container: container)
                DigestScheduler.scheduleNextMidnightRun()
                cloudStatus.refresh()
                Self.refreshLiveActivity(container: container)
                if PendingActionStore.consumePendingQuickCapture() {
                    quickCapture.isPresented = true
                }
            default:
                break
            }
        }
    }
}
