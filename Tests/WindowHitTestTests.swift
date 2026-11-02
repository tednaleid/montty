import AppKit
import Testing

/// montty's window content view is an NSHostingView, which is flipped. These
/// tests stand in a flipped container for it, with two panes stacked top and
/// bottom like a horizontal split.
@MainActor
struct WindowHitTestTests {
    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    private struct Fixture {
        let window: NSWindow
        let top: NSView
        let bottom: NSView
    }

    private func makeWindow(contentFlipped: Bool) -> Fixture {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let content: NSView = contentFlipped ? FlippedView() : NSView()
        window.contentView = content
        let size = content.bounds.size
        let half = size.height / 2
        let top = NSView()
        let bottom = NSView()
        // Place each pane by its on-screen position, whatever the flip.
        let topY = contentFlipped ? 0 : half
        let bottomY = contentFlipped ? half : 0
        top.frame = NSRect(x: 0, y: topY, width: size.width, height: half)
        bottom.frame = NSRect(x: 0, y: bottomY, width: size.width, height: half)
        content.addSubview(top)
        content.addSubview(bottom)
        return Fixture(window: window, top: top, bottom: bottom)
    }

    /// The window-coordinate location of a point inside `view`.
    private func windowPoint(in view: NSView) -> NSPoint {
        view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
    }

    @Test(arguments: [true, false])
    func clickInTopPaneHitsTopPane(contentFlipped: Bool) {
        let fixture = makeWindow(contentFlipped: contentFlipped)
        let hit = fixture.window.contentHitTest(windowPoint(in: fixture.top))
        #expect(hit === fixture.top)
    }

    @Test(arguments: [true, false])
    func clickInBottomPaneHitsBottomPane(contentFlipped: Bool) {
        let fixture = makeWindow(contentFlipped: contentFlipped)
        let hit = fixture.window.contentHitTest(windowPoint(in: fixture.bottom))
        #expect(hit === fixture.bottom)
    }
}
