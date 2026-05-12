// ABOUTME: SwiftUI rendering helpers for PaneTint, mainly the LinearGradient
// ABOUTME: that lets a single .fill() handle both solid and worktree-gradient cases.

import SwiftUI

extension PaneTint {
    /// A `LinearGradient` suitable for `.fill()`. When this tint is solid (no
    /// worktree), both stops are the same color, which renders identically to
    /// a solid fill -- so callers can use this everywhere without branching.
    func gradient(opacity: Double = 1.0) -> LinearGradient {
        let leading = (secondary ?? primary).swiftUIColor.opacity(opacity)
        let trailing = primary.swiftUIColor.opacity(opacity)
        return LinearGradient(
            colors: [leading, trailing],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
