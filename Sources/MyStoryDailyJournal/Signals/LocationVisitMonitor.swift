import Foundation
import CoreLocation
import SwiftData

/// Owns the app's one `CLLocationManager`. Two jobs, both from §3/§4:
///
/// - Place-level visits (`CLVisit` under Always authorization) are captured
///   live as they arrive from the system and written straight to the
///   day they occurred on — there's no API to pull visit history on
///   demand, so this is push, not pull, unlike the other signal providers.
/// - A one-shot, on-demand full-accuracy fix for M5's precise-location
///   flow lives here too, since `CLLocationManager` wants one delegate.
///
/// Reverse geocoding is cached by a coarse coordinate key so revisiting the
/// same place repeatedly doesn't repeatedly hit `CLGeocoder`.
@MainActor
final class LocationVisitMonitor: NSObject, CLLocationManagerDelegate, ObservableObject {
    static let shared = LocationVisitMonitor()

    /// Must match the key used in `NSLocationTemporaryUsageDescriptionDictionary`
    /// in Info.plist.
    static let fullAccuracyPurposeKey = "PreciseLocationForEntry"

    private let manager = CLLocationManager()
    private var geocodeCache: [String: String] = [:]
    private var oneShotContinuation: CheckedContinuation<CLLocation?, Never>?

    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization

    override init() {
        accuracyAuthorization = .reducedAccuracy
        super.init()
        manager.delegate = self
        accuracyAuthorization = manager.accuracyAuthorization
    }

    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    func startMonitoringVisitsIfAuthorized() {
        guard manager.authorizationStatus == .authorizedAlways else { return }
        manager.startMonitoringVisits()
    }

    func stopMonitoringVisits() {
        manager.stopMonitoringVisits()
    }

    /// M5: ask for the second, explicit full-accuracy grant. `purposeKey`
    /// must match a key in `NSLocationTemporaryUsageDescriptionDictionary`.
    func requestTemporaryFullAccuracy(purposeKey: String) {
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: purposeKey)
    }

    /// M5: an on-demand fix at a meaningful moment (app open, journal
    /// write) rather than continuous background tracking (§3).
    func requestOneShotFix() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            oneShotContinuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.accuracyAuthorization = manager.accuracyAuthorization
            self.startMonitoringVisitsIfAuthorized()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task { @MainActor in
            await self.persist(visit: visit)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.oneShotContinuation?.resume(returning: locations.last)
            self.oneShotContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.oneShotContinuation?.resume(returning: nil)
            self.oneShotContinuation = nil
        }
    }

    private func persist(visit: CLVisit) async {
        let date = visit.arrivalDate != .distantPast ? visit.arrivalDate : visit.departureDate
        guard date != .distantPast else { return }

        let placeName = await reverseGeocode(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)
        let payload = VisitPayload(
            placeName: placeName,
            latitude: visit.coordinate.latitude,
            longitude: visit.coordinate.longitude,
            isFullAccuracy: accuracyAuthorization == .fullAccuracy
        )

        let context = ModelContext(PersistenceController.makeContainer())
        let record = DayRecordRepository.record(for: date, in: context)
        let signal = DaySignal(kind: .visit, timestamp: date)
        signal.setPayload(payload)
        signal.dayRecord = record
        context.insert(signal)
        try? context.save()
    }

    private func reverseGeocode(latitude: Double, longitude: Double) async -> String {
        let key = "\(round(latitude * 100) / 100),\(round(longitude * 100) / 100)"
        if let cached = geocodeCache[key] { return cached }

        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let name = (try? await geocoder.reverseGeocodeLocation(location))?
            .first
            .flatMap { $0.name ?? $0.locality } ?? "Unknown place"

        geocodeCache[key] = name
        return name
    }
}
