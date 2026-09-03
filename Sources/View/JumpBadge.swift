import AppKit
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
            .foregroundStyle(color.readableLabelColor)
            .padding(.horizontal, large ? 20 : 4)
            .padding(.vertical, large ? 10 : 2)
            .background(
                RoundedRectangle(cornerRadius: large ? 12 : 3)
                    .fill(color.opacity(0.85))
            )
    }
}

private extension Color {
    /// Black on a light badge, white on a dark one, computed by the same
    /// luminance rule montty already uses for repo gradient hue matching.
    var readableLabelColor: Color {
        let nsColor = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        let rgb = RGB(
            r: UInt8((nsColor.redComponent * 255).rounded()),
            g: UInt8((nsColor.greenComponent * 255).rounded()),
            b: UInt8((nsColor.blueComponent * 255).rounded())
        )
        return rgb.isReadableWithDarkText ? .black : .white
    }
}
