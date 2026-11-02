// ABOUTME: Hit-tests a window-coordinate point against the window's content view,
// ABOUTME: correct for montty's flipped NSHostingView content view.

import AppKit

extension NSWindow {
    /// The deepest view under `locationInWindow`, searched from the content view.
    ///
    /// `hitTest(_:)` takes a point in the receiver's superview coordinates.
    /// Converting into the content view's own coordinates instead mirrors y
    /// when the content view is flipped, so a click in the top pane of a
    /// split resolves to the bottom pane.
    func contentHitTest(_ locationInWindow: NSPoint) -> NSView? {
        guard let contentView else { return nil }
        let location = contentView.superview?.convert(locationInWindow, from: nil)
            ?? locationInWindow
        return contentView.hitTest(location)
    }
}
