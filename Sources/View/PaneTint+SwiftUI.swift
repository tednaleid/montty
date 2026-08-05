// ABOUTME: SwiftUI rendering helpers for PaneTint, mainly the LinearGradient
// ABOUTME: that lets a single .fill() handle both solid and worktree-gradient cases.

import SwiftUI

extension PaneTint {
    /// A `LinearGradient` suitable for `.fill()`, blending evenly across the
    /// stops. A single stop repeats so it renders solid, letting callers use
    /// this everywhere without branching.
    func gradient(opacity: Double = 1.0) -> LinearGradient {
        var colors = stops.map { $0.swiftUIColor.opacity(opacity) }
        if colors.count == 1 { colors.append(colors[0]) }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}
