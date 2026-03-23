import SwiftUI

/// A rounded-rect badge showing a jump label (e.g., "a", "ab").
/// Used on both terminal surfaces (large) and minimap panes (small).
struct JumpBadge: View {
    let label: String
    let color: Color
    let large: Bool

    var body: some View {
        Text(label)
            .font(.system(
                size: large ? 48 : 16,
                weight: .bold,
                design: .monospaced
            ))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 20 : 4)
            .padding(.vertical, large ? 10 : 2)
            .background(
                RoundedRectangle(cornerRadius: large ? 12 : 3)
                    .fill(color.opacity(0.85))
            )
    }
}
