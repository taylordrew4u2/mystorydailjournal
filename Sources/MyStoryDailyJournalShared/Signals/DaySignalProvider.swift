import Foundation

/// A single background data source (Health, Calendar, Photos, Location, ...).
///
/// Each concrete provider (added milestone by milestone, see build spec §4
/// and §13 M3) owns exactly one `DaySignalKind` and is independently
/// disableable. A denied or unimplemented provider must degrade only its own
/// signal — digest assembly (§9) has to keep working with whatever subset of
/// providers returns results.
///
/// Deliberately not `Sendable`: several concrete providers wrap SDK types
/// (`HKHealthStore`, `EKEventStore`, `CLLocationManager`) that aren't
/// themselves Sendable. Digest assembly calls providers serially from one
/// isolation context rather than passing them across concurrency domains.
protocol DaySignalProvider {
    var kind: DaySignalKind { get }

    /// Whether the user has granted whatever system permission this provider
    /// needs. `false` means "skip me silently," not "fail the digest."
    func isAuthorized() async -> Bool

    /// Collect signals for the given local calendar day. Implementations
    /// must not throw for "no data today" — return an empty array instead.
    func collectSignals(for day: DateInterval) async throws -> [DaySignal]
}
