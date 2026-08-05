// ABOUTME: SwiftUI rendering helpers for PaneTint, mainly the LinearGradient
// ABOUTME: that lets a single .fill() handle both solid and worktree-gradient cases.

import SwiftUI

extension PaneTint {
    /// A `LinearGradient` suitable for `.fill()`. Stops render as equal-width
    /// hard-edged bands rather than a blend, so each color stays true enough to
    /// name at a glance in a narrow tab row. A single stop renders solid, so
    /// callers can use this everywhere without branching.
    func gradient(opacity: Double = 1.0) -> LinearGradient {
        let colors = stops.map { $0.swiftUIColor.opacity(opacity) }
        let bandWidth = 1.0 / Double(colors.count)
        let bands = colors.enumerated().flatMap { index, color in
            [
                Gradient.Stop(color: color, location: Double(index) * bandWidth),
                Gradient.Stop(color: color, location: Double(index + 1) * bandWidth)
            ]
        }
        return LinearGradient(stops: bands, startPoint: .leading, endPoint: .trailing)
    }
}
