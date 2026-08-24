import SwiftUI

/// A curated accent-color preset. Deliberately closed (not a free color
/// picker) because each preset needs a matching hand-finished home-screen
/// icon — see build spec §17. Backgrounds stay neutral system colors in
/// every preset; only the accent shifts.
enum Theme: String, CaseIterable, Identifiable, Codable {
    case ink
    case forest
    case rust
    case slate
    case plum
    case ochre
    case moss
    case midnight

    var id: String { rawValue }

    var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// Accent color, applied via `.tint()` to buttons, selected dates, and
    /// highlights. Alternate app icon switching lives in `AppIconManager`.
    var accent: Color {
        switch self {
        case .ink: Color(red: 0.12, green: 0.13, blue: 0.16)
        case .forest: Color(red: 0.13, green: 0.35, blue: 0.24)
        case .rust: Color(red: 0.62, green: 0.29, blue: 0.18)
        case .slate: Color(red: 0.29, green: 0.36, blue: 0.42)
        case .plum: Color(red: 0.38, green: 0.20, blue: 0.42)
        case .ochre: Color(red: 0.66, green: 0.49, blue: 0.15)
        case .moss: Color(red: 0.33, green: 0.40, blue: 0.24)
        case .midnight: Color(red: 0.10, green: 0.14, blue: 0.30)
        }
    }

    /// Matches an `CFBundleAlternateIcons` key once per-preset icon assets
    /// are added (build spec §17). `nil` means "use the primary icon."
    var alternateIconName: String? {
        self == .ink ? nil : "AppIcon-\(rawValue)"
    }
}
