// ABOUTME: NSWindowDelegate conformance that keeps libghostty surface focus in
// ABOUTME: step with the window's key state.

import Cocoa

extension AppDelegate: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        // If the window itself is first responder, no surface will accept
        // typing. Hand focus back to the active tab's pane.
        if let window, window.firstResponder === window,
           let surfaceID = tabStore.activeTab?.focusedSurfaceID,
           let surfaceView = surfaceView(for: surfaceID) {
            DispatchQueue.main.async {
                Ghostty.moveFocus(to: surfaceView)
            }
        }

        // Becoming key races responder updates, so let the responder chain
        // settle before reading isKeyWindow and firstResponder.
        DispatchQueue.main.async { [weak self] in
            self?.syncSurfaceFocus()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        syncSurfaceFocus()
    }
}
