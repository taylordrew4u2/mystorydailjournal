import DeviceActivity
import SwiftUI

/// The extension process itself — deliberately sandboxed by Apple so
/// nothing rendered here can be exported to the host app (§3). This is the
/// permanent architecture, not a stand-in for a future export API.
@main
struct MyStoryScreenTimeExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        DailyUsageReportScene()
    }
}
