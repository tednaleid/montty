// ABOUTME: Terminal tab colors mapped to ANSI-16 palette slots, plus the hue
// ABOUTME: families that keep two stops in one gradient tellable apart.

import Foundation

/// Terminal tab colors mapped to ANSI-16 palette slots.
/// Gray is reserved for directories not in a git repo.
enum TabColor: String, Codable, CaseIterable {
    case red, green, yellow, blue, magenta, cyan
    case brightRed, brightGreen, brightYellow, brightBlue, brightMagenta, brightCyan
    /// Used for dark themes (ANSI 7) or light themes (ANSI 0).
    case neutral
    /// Used for dark themes (ANSI 15) or light themes (ANSI 8).
    case neutralBright
    case gray
}

extension TabColor {
    /// Hue families collapse each base/bright pair, which read as one color at a
    /// glance. Knockout removes a whole family so a gradient never sets green
    /// beside brightGreen.
    enum HueFamily: Hashable {
        case red, green, yellow, blue, magenta, cyan, neutral
    }

    var hueFamily: HueFamily {
        switch self {
        case .red, .brightRed: .red
        case .green, .brightGreen: .green
        case .yellow, .brightYellow: .yellow
        case .blue, .brightBlue: .blue
        case .magenta, .brightMagenta: .magenta
        case .cyan, .brightCyan: .cyan
        case .neutral, .neutralBright, .gray: .neutral
        }
    }
}
