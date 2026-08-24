import WidgetKit
import SwiftUI
import AppIntents

struct QuickTagEntry: TimelineEntry {
    let date: Date
    let tag: PresetTag
}

struct QuickTagProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickTagEntry {
        QuickTagEntry(date: .now, tag: .good)
    }

    func snapshot(for configuration: TagWidgetConfigurationIntent, in context: Context) async -> QuickTagEntry {
        QuickTagEntry(date: .now, tag: configuration.tag)
    }

    func timeline(
        for configuration: TagWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<QuickTagEntry> {
        // A single, non-expiring entry: this widget's content never changes
        // on its own, only in response to the user's own tap (which forces
        // a reload via `WidgetCenter.reloadAllTimelines()` in `TagLogger`).
        Timeline(entries: [QuickTagEntry(date: .now, tag: configuration.tag)], policy: .never)
    }
}

/// A Lock Screen (and Home Screen accessory) widget that logs one preset
/// tag with a single tap — the "no typing at all" half of §5 item 2. The
/// button's `AppIntent` runs without opening the app.
struct QuickTagWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuickTagEntry

    var body: some View {
        Button(intent: LogTagIntent(tag: entry.tag)) {
            switch family {
            case .accessoryCircular:
                Text(String(entry.tag.rawValue.prefix(1)))
                    .font(.title2.weight(.semibold))
            default:
                Label(entry.tag.rawValue, systemImage: "checkmark.circle")
                    .font(.footnote.weight(.medium))
            }
        }
        .buttonStyle(.plain)
    }
}

struct QuickTagWidget: Widget {
    let kind = "QuickTagWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: TagWidgetConfigurationIntent.self,
            provider: QuickTagProvider()
        ) { entry in
            QuickTagWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Tag")
        .description("Log a one-tap tag without opening the app or typing anything.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
