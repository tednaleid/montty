import Foundation

enum TabColor: Codable, Equatable {
    case preset(PresetColor)
    case auto

    enum PresetColor: String, Codable, CaseIterable {
        case red, orange, yellow, green, blue, indigo, purple, pink, brown, gray
    }
}
