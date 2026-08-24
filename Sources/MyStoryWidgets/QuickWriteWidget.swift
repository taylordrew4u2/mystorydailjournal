import WidgetKit
import SwiftUI

struct QuickWriteEntry: TimelineEntry {
    let date: Date
}

struct QuickWriteProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickWriteEntry {
        QuickWriteEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickWriteEntry) -> Void) {
        completion(QuickWriteEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickWriteEntry>) -> Void) {
        completion(Timeline(entries: [QuickWriteEntry(date: .now)], policy: .never))
    }
}

/// The "opens a bare text field" half of §5 item 2. A widget can't host an
/// interactive text field itself, so a tap opens the app straight into
/// `QuickCaptureSheet` via `widgetURL` — no day list, no prior screens.
struct QuickWriteWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "square.and.pencil")
                .font(.title3)
            if family != .accessoryCircular {
                Text("Write today")
                    .font(.caption2.weight(.medium))
            }
        }
        .widgetURL(QuickCaptureDeepLink.url)
    }
}

struct QuickWriteWidget: Widget {
    let kind = "QuickWriteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickWriteProvider()) { _ in
            QuickWriteWidgetView()
        }
        .configurationDisplayName("Write Today")
        .description("Open a bare text field to write today's entry.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall])
    }
}
