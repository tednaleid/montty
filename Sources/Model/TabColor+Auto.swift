import Foundation

extension TabColor {
    /// Derive a preset color from a directory path by hashing.
    /// Same directory always produces the same color.
    static func colorForDirectory(_ dir: String?) -> PresetColor {
        guard let dir else { return .gray }
        let hash = dir.utf8.reduce(UInt64(0)) { ($0 &+ UInt64($1)) &* 31 }
        let colors = PresetColor.allCases
        return colors[Int(hash % UInt64(colors.count))]
    }
}
