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
