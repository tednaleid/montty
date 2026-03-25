import AppKit
import SwiftUI

/// Create a small colored circle image for use in menus.
/// macOS menus force SF Symbols to template mode, so we draw our own.
private func colorSwatch(_ color: Color, checked: Bool) -> NSImage {
    let size: CGFloat = 14
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        NSColor(color).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
        if checked {
            // Draw a small white checkmark
            let checkmark = NSBezierPath()
            checkmark.move(to: NSPoint(x: 4, y: 7))
            checkmark.line(to: NSPoint(x: 6.5, y: 4.5))
            checkmark.line(to: NSPoint(x: 10, y: 9.5))
            NSColor.white.setStroke()
            checkmark.lineWidth = 1.5
            checkmark.lineCapStyle = .round
            checkmark.lineJoinStyle = .round
            checkmark.stroke()
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
                Label {
                    Text(color.rawValue.capitalized)
                } icon: {
                    Image(nsImage: colorSwatch(
                        color.swiftUIColor,
                        checked: color == currentColor
                    ))
                }
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
