import Foundation

/// Remembers what the writer said is at a place, so they're only ever
/// asked once. Once "480 Larkin Street" is confirmed to be Blue Bottle,
/// every future day that geocodes to that address — or lands within about
/// a block of those coordinates — writes "Blue Bottle" straight away.
///
/// A local preference, not journal content: same reasoning as
/// `SettingsStore` (§7), so it lives in `UserDefaults` rather than the
/// synced store. Names the user typed themselves never leave the device.
enum PlaceAliasStore {
    /// Every alias known, keyed both by normalized place name and by
    /// coarse coordinate. Handed to `DigestComposer` as a plain dictionary
    /// so composition stays a pure function of its inputs.
    static func aliases(defaults: UserDefaults = .standard) -> [String: String] {
        defaults.dictionary(forKey: Keys.aliases) as? [String: String] ?? [:]
    }

    /// The name to write for a place, or nil when nothing's been confirmed.
    /// Coordinates win over the name: the same corner can reverse-geocode
    /// to slightly different strings on different days.
    static func name(
        for rawName: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        defaults: UserDefaults = .standard
    ) -> String? {
        resolve(rawName: rawName, latitude: latitude, longitude: longitude, in: aliases(defaults: defaults))
    }

    /// Pure lookup against an already-loaded alias map.
    static func resolve(
        rawName: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        in aliases: [String: String]
    ) -> String? {
        guard !aliases.isEmpty else { return nil }
        if let latitude, let longitude, let byCoordinate = aliases[coordinateKey(latitude: latitude, longitude: longitude)] {
            return byCoordinate
        }
        return aliases[nameKey(rawName)]
    }

    static func record(
        name: String,
        for rawName: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        defaults: UserDefaults = .standard
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRaw = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedRaw.isEmpty else { return }

        var stored = aliases(defaults: defaults)
        stored[nameKey(trimmedRaw)] = trimmedName
        if let latitude, let longitude {
            stored[coordinateKey(latitude: latitude, longitude: longitude)] = trimmedName
        }
        defaults.set(stored, forKey: Keys.aliases)
    }

    static func removeAll(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: Keys.aliases)
    }

    static func nameKey(_ rawName: String) -> String {
        rawName
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Three decimal places is roughly a hundred metres — close enough that
    /// two fixes at the same café collide, far enough that neighbouring
    /// shops don't.
    static func coordinateKey(latitude: Double, longitude: Double) -> String {
        let lat = (latitude * 1000).rounded() / 1000
        let lon = (longitude * 1000).rounded() / 1000
        return String(format: "@%.3f,%.3f", lat, lon)
    }

    private enum Keys {
        static let aliases = "places.confirmedNames"
    }
}
