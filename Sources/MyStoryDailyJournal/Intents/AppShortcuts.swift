import AppIntents

/// Makes `LogTodayIntent` discoverable to Siri and the Shortcuts app without
/// the user having to build anything themselves (§5 item 3).
struct MyStoryAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogTodayIntent(),
            phrases: [
                "Log my day in \(.applicationName)",
                "Add a journal entry in \(.applicationName)",
            ],
            shortTitle: "Log My Day",
            systemImageName: "book"
        )
    }
}
