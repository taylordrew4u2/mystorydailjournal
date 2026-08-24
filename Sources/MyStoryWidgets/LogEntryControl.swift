import SwiftUI
import WidgetKit

/// A Control Center control (§3, §15) — part of the persistent-surfaces
/// stack that stands in for the Android-style ongoing notification iOS
/// doesn't have. Tapping opens the app straight to quick capture via
/// `OpenQuickCaptureControlIntent`.
///
/// Version-sensitive per §18: confirm `ControlWidget`'s current API shape
/// and availability against the SDK this is actually built with —
/// `ControlWidget` was new enough in iOS 18 that this is the area most
/// likely to have shifted since.
struct LogEntryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.mystorydailyjournal.app.widgets.quickcapture-control") {
            ControlWidgetButton(action: OpenQuickCaptureControlIntent()) {
                Label("Write Today", systemImage: "square.and.pencil")
            }
        }
        .displayName("Write Today")
        .description("Opens My Story to a bare text field for today's entry.")
    }
}
