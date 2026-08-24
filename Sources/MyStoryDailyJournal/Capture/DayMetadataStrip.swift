import SwiftUI

/// The "place, weather, tags, and people" metadata strip from §16. Place and
/// weather are read-only — they come from `.visit`/`.weather` signals the
/// day already collected, never typed in — so this only ever renders what
/// the day already knows, alongside the always-available tag/people chips.
struct DayMetadataStrip: View {
    let record: DayRecord

    private var place: String? {
        (record.signals ?? [])
            .filter { $0.kind == .visit }
            .compactMap { $0.payload(as: VisitPayload.self) }
            .first { !$0.placeName.isEmpty }?
            .placeName
    }

    private var weather: WeatherPayload? {
        (record.signals ?? [])
            .first { $0.kind == .weather }?
            .payload(as: WeatherPayload.self)
    }

    var body: some View {
        if place != nil || weather != nil {
            HStack(spacing: 12) {
                if let place {
                    Label(place, systemImage: "mappin.and.ellipse")
                }
                if let weather {
                    Label(weatherText(weather), systemImage: "cloud.sun")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func weatherText(_ weather: WeatherPayload) -> String {
        guard let high = weather.highTemperatureCelsius else { return weather.conditionDescription }
        return "\(weather.conditionDescription), \(Int(high))°"
    }
}
