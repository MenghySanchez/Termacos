import SwiftUI
import AppKit

/// Adaptive design tokens. Colors track the system light/dark appearance
/// (never a forced theme) so the app behaves like a native macOS citizen.
enum Theme {
    /// Terminal-green accent used for the primary "connect" action and
    /// success/connected states — tuned separately per appearance for
    /// correct contrast in both modes.
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(red: 0.30, green: 0.82, blue: 0.55, alpha: 1)
            : NSColor(red: 0.09, green: 0.55, blue: 0.32, alpha: 1)
    })

    static let danger = Color(nsColor: .systemRed)
    static let warning = Color(nsColor: .systemOrange)

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
    }

    static let cornerRadius: CGFloat = 8
}

extension Font {
    /// Monospaced style for technical, copy-pasteable strings (host:port, key paths).
    static func mono(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
