import Foundation
import CoreLocation

/// Unlike the other providers, visits are captured live by
/// `LocationVisitMonitor` as `CLVisit` events arrive — there's no API to
/// pull visit history for an arbitrary past day. `collectSignals` always
/// returns empty; by digest time, any visits for the day are already
/// attached to that day's `DayRecord`. This type mainly exists so the
/// wizard's signal toggles (§7 step 4) have one consistent interface across
/// all four signals.
struct LocationSignalProvider: DaySignalProvider {
    let kind: DaySignalKind = .visit

    func isAuthorized() async -> Bool {
        CLLocationManager().authorizationStatus == .authorizedAlways
    }

    func collectSignals(for day: DateInterval) async throws -> [DaySignal] {
        []
    }
}
