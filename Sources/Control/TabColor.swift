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

    /// The ANSI-16 SGR foreground code this name maps to, for showing a
    /// swatch beside the name in terminal output.
    var ansiCode: Int {
        switch self {
        case .red: 31
        case .green: 32
        case .yellow: 33
        case .blue: 34
        case .magenta: 35
        case .cyan: 36
        case .neutral: 37
        case .gray: 90
        case .brightRed: 91
        case .brightGreen: 92
        case .brightYellow: 93
        case .brightBlue: 94
        case .brightMagenta: 95
        case .brightCyan: 96
        case .neutralBright: 97
        }
    }
}
