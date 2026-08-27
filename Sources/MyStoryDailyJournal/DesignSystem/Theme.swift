import SwiftUI
import UIKit

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
    ///
    /// Dynamic per appearance: the light-mode values are deep, ink-like
    /// hues, which vanish against a dark background — in dark mode each
    /// palette swaps to a brighter variant of the same hue so tinted text
    /// and controls stay readable.
    var accent: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkVariant : lightVariant
        })
    }

    private var lightVariant: UIColor {
        switch self {
        case .ink: UIColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)
        case .forest: UIColor(red: 0.13, green: 0.35, blue: 0.24, alpha: 1)
        case .rust: UIColor(red: 0.62, green: 0.29, blue: 0.18, alpha: 1)
        case .slate: UIColor(red: 0.29, green: 0.36, blue: 0.42, alpha: 1)
        case .plum: UIColor(red: 0.38, green: 0.20, blue: 0.42, alpha: 1)
        case .ochre: UIColor(red: 0.66, green: 0.49, blue: 0.15, alpha: 1)
        case .moss: UIColor(red: 0.33, green: 0.40, blue: 0.24, alpha: 1)
        case .midnight: UIColor(red: 0.10, green: 0.14, blue: 0.30, alpha: 1)
        }
    }

    private var darkVariant: UIColor {
        switch self {
        case .ink: UIColor(red: 0.78, green: 0.80, blue: 0.85, alpha: 1)
        case .forest: UIColor(red: 0.42, green: 0.72, blue: 0.55, alpha: 1)
        case .rust: UIColor(red: 0.88, green: 0.52, blue: 0.38, alpha: 1)
        case .slate: UIColor(red: 0.58, green: 0.69, blue: 0.78, alpha: 1)
        case .plum: UIColor(red: 0.74, green: 0.52, blue: 0.78, alpha: 1)
        case .ochre: UIColor(red: 0.87, green: 0.70, blue: 0.36, alpha: 1)
        case .moss: UIColor(red: 0.62, green: 0.72, blue: 0.46, alpha: 1)
        case .midnight: UIColor(red: 0.52, green: 0.62, blue: 0.92, alpha: 1)
        }
    }

    /// Matches an `CFBundleAlternateIcons` key once per-preset icon assets
    /// are added (build spec §17). `nil` means "use the primary icon."
    var alternateIconName: String? {
        self == .ink ? nil : "AppIcon-\(rawValue)"
    }
}
