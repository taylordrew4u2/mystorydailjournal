import WidgetKit
import SwiftUI

@main
struct MyStoryWidgetsBundle: WidgetBundle {
    var body: some Widget {
        QuickTagWidget()
        QuickWriteWidget()
        JournalLiveActivity()
        LogEntryControl()
    }
}
