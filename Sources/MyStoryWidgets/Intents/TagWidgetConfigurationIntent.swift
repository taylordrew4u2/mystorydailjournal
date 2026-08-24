import AppIntents

/// Lets the user pick, per widget instance, which preset tag the Lock
/// Screen widget logs — set via the widget's own edit UI (long-press,
/// then "Edit Widget"), not inside this app.
struct TagWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Tag"
    static var description = IntentDescription("Pick which one-tap tag this widget logs.")

    @Parameter(title: "Tag", default: .good)
    var tag: PresetTag
}
