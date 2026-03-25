import AppKit
import SwiftUI

/// Create a colored rounded rectangle for use in menus.
/// macOS menus force SF Symbols to template mode, so we draw our own.
private func colorSwatch(_ color: Color, checked: Bool) -> NSImage {
    let width: CGFloat = 48
    let height: CGFloat = 14
    let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
        let inset = rect.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: inset, xRadius: 3, yRadius: 3)
        NSColor(color).setFill()
        path.fill()
        if checked {
            NSColor.white.setStroke()
            path.lineWidth = 4
            path.stroke()
        }
        return true
    }
    image.isTemplate = false
    return image
}

struct TabColorPicker: View {
    let currentColor: TabColor
    /// Called with a color to set an override, or nil to clear the override.
    let onSelect: (TabColor?) -> Void

    var body: some View {
        ForEach(TabColor.allCases.filter { $0 != .gray }, id: \.self) { color in
            Button {
                onSelect(color)
            } label: {
                Image(nsImage: colorSwatch(
                    color.swiftUIColor,
                    checked: color == currentColor
                ))
            }
        }

        Divider()

        Button {
            onSelect(nil)
        } label: {
            Label("Reset", systemImage: "arrow.counterclockwise")
        }
    }
}
