// ABOUTME: Starts an AppKit drag of a sidebar tab from behind its SwiftUI row, watching the
// ABOUTME: mouse without taking its events, and reports where the drag was released.

import AppKit
import SwiftUI

struct TabDragSource: NSViewRepresentable {
    let tabID: UUID
    /// Drawn as the image that follows the cursor.
    let title: String
    let onBegin: (UUID) -> Void
    /// The tab and where it was released, in screen coordinates, or nil when
    /// the drag was cancelled with Escape.
    let onEnd: (UUID, CGPoint?) -> Void

    func makeNSView(context: Context) -> TabDragSourceView {
        let view = TabDragSourceView()
        update(view)
        return view
    }

    func updateNSView(_ view: TabDragSourceView, context: Context) {
        update(view)
    }

    private func update(_ view: TabDragSourceView) {
        view.tabID = tabID
        view.title = title
        view.onBegin = onBegin
        view.onEnd = onEnd
    }
}

/// SwiftUI's own drag never says where a drag ended when nothing accepted it,
/// which is the one thing a tear-off needs. An AppKit dragging session does.
final class TabDragSourceView: NSView, NSDraggingSource {
    var tabID = UUID()
    var title = ""
    var onBegin: ((UUID) -> Void)?
    var onEnd: ((UUID, CGPoint?) -> Void)?

    private var monitor: Any?
    private var pressedAt: NSPoint?

    /// How far the mouse travels with the button down before it is a drag.
    private static let dragThreshold: CGFloat = 4

    /// Never the target of a click: the SwiftUI row in front keeps every
    /// gesture it has.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.observe(event)
            return event
        }
    }

    private func observe(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            pressedAt = isOverRow(event) && !isEditingText ? event.locationInWindow : nil
        case .leftMouseDragged:
            guard let pressedAt else { return }
            let moved = hypot(event.locationInWindow.x - pressedAt.x,
                              event.locationInWindow.y - pressedAt.y)
            guard moved > Self.dragThreshold else { return }
            self.pressedAt = nil
            beginDrag(with: event)
        default:
            pressedAt = nil
        }
    }

    private func isOverRow(_ event: NSEvent) -> Bool {
        event.window === window && bounds.contains(convert(event.locationInWindow, from: nil))
    }

    /// A press inside a name being edited selects text.
    private var isEditingText: Bool {
        window?.firstResponder is NSText
    }

    private func beginDrag(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: TabDragPayload.pasteboardItem(for: tabID))
        let image = previewImage()
        let cursor = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(origin: cursor, size: image.size), contents: image)
        onBegin?(tabID)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    private func previewImage() -> NSImage {
        let text = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor
        ])
        let padding: CGFloat = 4
        let size = NSSize(
            width: ceil(text.size().width) + padding * 2,
            height: ceil(text.size().height) + padding * 2
        )
        return NSImage(size: size, flipped: false) { _ in
            text.draw(at: NSPoint(x: padding, y: padding))
            return true
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    /// A drag released over its own window that nothing accepted slides back
    /// to its row. One released anywhere else is leaving the window, so it
    /// does not.
    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        session.animatesToStartingPositionsOnCancelOrFail =
            window?.frame.contains(screenPoint) ?? true
    }

    /// AppKit ends a drag the same way for Escape as for a release over
    /// nothing. A release lets the mouse button up and Escape does not, so
    /// the button still being down is what tells them apart.
    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
        let cancelled = NSEvent.pressedMouseButtons & 1 != 0
        onEnd?(tabID, cancelled ? nil : screenPoint)
    }
}
