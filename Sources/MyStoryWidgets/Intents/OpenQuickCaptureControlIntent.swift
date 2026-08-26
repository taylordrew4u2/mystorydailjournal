import AppIntents

/// The Control Center control's action. Rather than guessing at App
/// Intents' exact app-opening deep-link API (version-sensitive per §18),
/// this writes a plain flag to the shared `PendingActionStore` and opens
/// the app; the app's own `scenePhase == .active` handling — already
/// certain to run on every foreground — is what actually presents the
/// quick-capture sheet.
struct OpenQuickCaptureControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Write Today"
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        PendingActionStore.requestQuickCapture()
        return .result()
    }
}
