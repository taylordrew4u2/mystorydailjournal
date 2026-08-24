import SwiftUI
import DeviceActivity

/// A live, display-only Screen Time panel (§3). `DeviceActivityReport`
/// renders inside a sandboxed extension process that Apple's own DTS
/// engineers have confirmed on the record is deliberately read-only, so no
/// number from it can ever reach `bodyText` or a stored `DaySignal` — this
/// view genuinely is the entire feature, permanently, not a placeholder
/// waiting on an API that extracts data. Shown only on today, since
/// Screen Time reporting is inherently live rather than a queryable past
/// record.
///
/// **Version-sensitive** (§18): `DeviceActivityFilter`'s exact initializer
/// and `DeviceActivityReport.Context`/`Scene` shapes have moved across iOS
/// releases and are sparsely documented — confirm both this view and the
/// matching `MyStoryScreenTime` extension target against the SDK this is
/// actually built with before shipping.
struct ScreenTimePanel: View {
    @StateObject private var auth = ScreenTimeAuthorizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Screen Time")
                .font(.caption)
                .foregroundStyle(.secondary)

            if auth.isAuthorized {
                DeviceActivityReport(Self.context, filter: Self.filter)
                    .frame(minHeight: 140)
            } else {
                Button("Show Screen Time") {
                    Task { await auth.requestAuthorization() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
    }

    /// Must match the `context` the `MyStoryScreenTime` extension's
    /// `DeviceActivityReportScene` declares.
    static let context = DeviceActivityReport.Context(rawValue: "dailyUsage")

    static var filter: DeviceActivityFilter {
        let start = DateUtilities.startOfDay(for: .now)
        return DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: start, end: .now)),
            users: .all,
            devices: .init([.iPhone])
        )
    }
}
