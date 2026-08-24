import DeviceActivity
import SwiftUI

/// Renders whatever `DeviceActivityResults` the system hands this
/// extension into a plain, minimal usage view. `context` must match
/// `ScreenTimePanel.context` in the host app.
struct DailyUsageReportScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .init(rawValue: "dailyUsage")

    let content: (DailyUsageConfiguration) -> DailyUsageView = { configuration in
        DailyUsageView(configuration: configuration)
    }

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> DailyUsageConfiguration {
        var totalDuration: TimeInterval = 0
        for await activityData in data {
            for await segment in activityData.activitySegments {
                totalDuration += segment.totalActivityDuration
            }
        }
        return DailyUsageConfiguration(totalDuration: totalDuration)
    }
}

struct DailyUsageConfiguration {
    let totalDuration: TimeInterval
}

struct DailyUsageView: View {
    let configuration: DailyUsageConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today so far")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formatted(configuration.totalDuration))
                .font(.title2.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private func formatted(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0m"
    }
}
