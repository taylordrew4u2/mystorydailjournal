import Foundation
import MapKit

/// A real place Maps knows about at the coordinates the phone recorded —
/// its name and what kind of place it is ("Cobb's Comedy Club", *comedy
/// club*), so a guided question can offer the actual venue rather than
/// asking the writer to type an address back at themselves.
struct NearbyPlace: Identifiable, Equatable, Sendable {
    var name: String
    /// A plain-language category from Maps ("café", "music venue"), when it
    /// has one.
    var categoryLabel: String?
    var distanceMeters: Double

    var id: String { "\(name)|\(categoryLabel ?? "")" }

    /// Chip text: the venue, with what it is when Maps says so.
    var displayName: String {
        guard let categoryLabel else { return name }
        return "\(name) · \(categoryLabel)"
    }
}

/// Looks up what's actually at a coordinate, via MapKit's points-of-interest
/// search.
///
/// Like reverse geocoding and WeatherKit (§4, PRIVACY.md), this is a query
/// to Apple's own service on the user's behalf: a coordinate goes out, place
/// names come back, and nothing about the journal is sent. Results are cached
/// per coarse coordinate for the life of the app run, so paging back and
/// forth through the questions doesn't re-query.
///
/// **Version-sensitive** (§18): `MKPointOfInterestCategory` gains cases with
/// almost every release, so the label mapping below falls back to a
/// humanized raw value rather than assuming a fixed set.
@MainActor
enum PlaceLookup {
    /// How far around the recorded coordinate to look. A recorded visit is
    /// only place-accurate to begin with, and a wider net just fills the
    /// chips with the rest of the block.
    static let searchRadiusMeters: CLLocationDistance = 150

    private static var cache: [String: [NearbyPlace]] = [:]

    static func nearbyPlaces(
        latitude: Double,
        longitude: Double,
        limit: Int = 5
    ) async -> [NearbyPlace] {
        let key = PlaceAliasStore.coordinateKey(latitude: latitude, longitude: longitude)
        if let cached = cache[key] { return Array(cached.prefix(limit)) }

        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let request = MKLocalPointsOfInterestRequest(center: center, radius: searchRadiusMeters)

        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }

        let origin = CLLocation(latitude: latitude, longitude: longitude)
        var places: [NearbyPlace] = []
        for item in response.mapItems {
            guard let name = item.name, !name.isEmpty else { continue }
            let coordinate = item.placemark.coordinate
            let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: origin)
            places.append(NearbyPlace(
                name: name,
                categoryLabel: label(for: item.pointOfInterestCategory),
                distanceMeters: distance
            ))
        }

        // Nearest first, and only one entry per venue name — Maps happily
        // returns the same shop twice when it has two entrances.
        var seen = Set<String>()
        let ordered = places
            .sorted { $0.distanceMeters < $1.distanceMeters }
            .filter { seen.insert($0.name.lowercased()).inserted }

        cache[key] = ordered
        return Array(ordered.prefix(limit))
    }

    /// Plain-language name for a Maps category. The explicit cases cover the
    /// ones a journal actually needs to read well; anything newer falls back
    /// to its own raw value, humanized.
    nonisolated static func label(for category: MKPointOfInterestCategory?) -> String? {
        guard let category else { return nil }
        switch category {
        case .cafe: return "café"
        case .restaurant: return "restaurant"
        case .bakery: return "bakery"
        case .brewery: return "brewery"
        case .winery: return "winery"
        case .nightlife: return "bar"
        case .theater: return "theater"
        case .movieTheater: return "cinema"
        case .museum: return "museum"
        case .library: return "library"
        case .park: return "park"
        case .nationalPark: return "national park"
        case .beach: return "beach"
        case .campground: return "campground"
        case .fitnessCenter: return "gym"
        case .stadium: return "stadium"
        case .store: return "store"
        case .foodMarket: return "food market"
        case .pharmacy: return "pharmacy"
        case .hospital: return "hospital"
        case .school: return "school"
        case .university: return "university"
        case .hotel: return "hotel"
        case .airport: return "airport"
        case .publicTransport: return "transit stop"
        case .parking: return "parking"
        case .bank: return "bank"
        case .postOffice: return "post office"
        default: return humanized(category.rawValue)
        }
    }

    /// `MKPOICategoryMusicVenue` → "music venue".
    nonisolated static func humanized(_ rawValue: String) -> String? {
        var name = rawValue
        if let range = name.range(of: "MKPOICategory") {
            name.removeSubrange(range)
        }
        guard !name.isEmpty else { return nil }

        var words: [String] = []
        var current = ""
        for character in name {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }

        let humanized = words.joined(separator: " ").lowercased()
        return humanized.isEmpty ? nil : humanized
    }
}
