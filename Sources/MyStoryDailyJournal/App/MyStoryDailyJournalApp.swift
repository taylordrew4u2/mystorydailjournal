import SwiftUI
import SwiftData
import UserNotifications

@main
struct MyStoryDailyJournalApp: App {
    let container: ModelContainer
    @StateObject private var settings: SettingsStore
    @StateObject private var appLock: AppLockManager
    @StateObject private var quickCapture = QuickCaptureCoordinator()
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
        // the foreground catch-up on scenePhase below is the reliable half).
        DigestScheduler.register(container: container)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(settings)
                .environmentObject(appLock)
                .environmentObject(quickCapture)
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
            default:
                break
            }
        }
    }
}
