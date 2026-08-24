import WidgetKit
import SwiftUI
import ActivityKit

/// Renders `JournalActivityAttributes` on the Lock Screen and in the
/// Dynamic Island. Shows only the prompt — whether today is journaled yet
/// — never any journal content, since `ContentState` has nowhere to carry
/// content in the first place (§5 item 2).
struct JournalLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JournalActivityAttributes.self) { context in
            LockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text(prompt(for: context.state))
                        .font(.footnote)
                }
            } compactLeading: {
                Image(systemName: context.state.isJournaled ? "checkmark.circle" : "book")
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Image(systemName: context.state.isJournaled ? "checkmark.circle" : "book")
            }
        }
    }

    private func prompt(for state: JournalActivityAttributes.ContentState) -> String {
        state.isJournaled ? "\(state.dateDescription) is written" : "Write \(state.dateDescription)"
    }
}

private struct LockScreenView: View {
    let state: JournalActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state.isJournaled ? "checkmark.circle" : "book")
            Text(state.isJournaled ? "\(state.dateDescription) is written" : "Write \(state.dateDescription)")
                .font(.subheadline.weight(.medium))
            Spacer()
        }
        .padding()
    }
}
