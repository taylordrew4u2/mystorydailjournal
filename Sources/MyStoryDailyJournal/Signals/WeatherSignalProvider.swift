import Foundation
import WeatherKit
import CoreLocation

/// "Free contextual color for the digest" (§9). No permission prompt —
/// WeatherKit needs only the WeatherKit entitlement, not a runtime grant.
///
/// Version-sensitive per build spec §18: WeatherKit's historical-lookup
/// surface is the part most likely to have moved by the time this is built
/// against a real SDK — confirm `WeatherService`'s current API for a
/// specific past day before shipping. This implementation degrades to no
/// signal (never throws to the caller) if the lookup fails or the day falls
/// outside whatever window the SDK actually supports.
struct WeatherSignalProvider: DaySignalProvider {
    let kind: DaySignalKind = .weather

    private let service = WeatherService.shared

    /// Weather needs a place, which this app only has once a visit or a
    /// one-shot fix has produced one — so it's supplied by the caller
    /// (`DigestEngine`) rather than queried independently like the other
    /// providers.
    func isAuthorized() async -> Bool { true }

    func collectSignals(for day: DateInterval) async throws -> [DaySignal] {
        []
    }

    func collectSignal(for day: DateInterval, at coordinate: CLLocationCoordinate2D) async -> DaySignal? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let dayWeather = try? await service.weather(for: location, including: .daily) else {
            return nil
        }
        guard let matchingDay = dayWeather.forecast.first(where: {
            day.contains($0.date) || Calendar.current.isDate($0.date, inSameDayAs: day.start)
        }) else {
            return nil
        }

        let payload = WeatherPayload(
            conditionDescription: matchingDay.condition.plainDescription,
            highTemperatureCelsius: matchingDay.highTemperature.converted(to: .celsius).value,
            lowTemperatureCelsius: matchingDay.lowTemperature.converted(to: .celsius).value
        )
        let signal = DaySignal(kind: .weather, timestamp: day.start)
        signal.setPayload(payload)
        return signal
    }
}

private extension WeatherCondition {
    /// WeatherKit doesn't ship a plain-text label for every condition case,
    /// so this covers the common ones and falls back generically.
    var plainDescription: String {
        switch self {
        case .clear, .mostlyClear: "Clear skies"
        case .partlyCloudy: "Partly cloudy"
        case .cloudy, .mostlyCloudy: "Cloudy"
        case .rain, .heavyRain: "Rain"
        case .drizzle: "Light rain"
        case .snow, .heavySnow: "Snow"
        case .thunderstorms: "Thunderstorms"
        case .foggy, .haze: "Fog"
        case .windy: "Windy"
        default: "Mixed conditions"
        }
    }
}
