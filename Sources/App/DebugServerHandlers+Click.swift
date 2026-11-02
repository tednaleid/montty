// ABOUTME: Simulates a left click on a surface by posting real mouse events to
// ABOUTME: the app queue, so local event monitors (split focus) see the click.
#if DEBUG
import AppKit
import Network

extension DebugServer {
    /// Clicks the center of the named surface (or the focused one). The events
    /// go through `NSApp.postEvent`, not straight to the view, because split
    /// focus transfer happens in a local event monitor that only runs for
    /// events dispatched from the app's queue.
    static func handleClick(surfaceID: String?, connection: NWConnection) {
        DispatchQueue.main.async {
            guard let view = surface(forID: surfaceID), let window = view.window else {
                sendJSON(["error": "No surface found"], status: 404, connection: connection)
                return
            }
            let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let event = NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
                ) else {
                    sendJSON(["error": "Could not create mouse event"], status: 500, connection: connection)
                    return
                }
                NSApp.postEvent(event, atStart: false)
            }
            sendJSON([
                "ok": true,
                "surface": view.id.uuidString,
                "window_point": ["x": point.x, "y": point.y]
            ], connection: connection)
        }
    }
}
#endif
