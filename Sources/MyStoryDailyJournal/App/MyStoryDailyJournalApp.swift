import SwiftUI
import SwiftData
import UserNotifications

@main
struct MyStoryDailyJournalApp: App {
    let container: ModelContainer
    @StateObject private var settings: SettingsStore
    @StateObject private var appLock: AppLockManager
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
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(settings)
                .environmentObject(appLock)
                .tint(settings.theme.accent)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                appLock.sceneDidEnterBackground()
            case .active:
                appLock.sceneDidBecomeActive()
            default:
                break
            }
        }
    }
}
