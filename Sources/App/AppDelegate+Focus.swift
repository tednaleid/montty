// ABOUTME: NSWindowDelegate conformance that keeps libghostty surface focus in
// ABOUTME: step with the window's key state.

import Cocoa

extension AppDelegate: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        // If the window itself is first responder, no surface will accept
        // typing. Hand focus back to the active tab's pane.
        //
        // This guard only covers the window-holds-the-responder case. It does
        // NOT cover the more common repair: a surface that is still first
        // responder but whose `focused` flag went stale `false` across a
        // deactivate/reactivate cycle. There `firstResponder === window` is
        // false, so this branch is skipped entirely, and the fix happens
        // solely in the unconditional syncSurfaceFocus() call below.
        if let window, window.firstResponder === window,
           let surfaceID = tabStore.activeTab?.focusedSurfaceID,
           let surfaceView = surfaceView(for: surfaceID) {
            // This hop is load-bearing, not redundant, even though
            // Ghostty.moveFocus already dispatches its own work onto the main
            // queue. Without it, makeFirstResponder would land before
            // syncSurfaceFocus() below runs, emitting this surface's focus
            // report ahead of the other surfaces' blurs -- exactly the
            // ordering syncSurfaceFocus's doc comment says must not happen.
            // Deferring here makes makeFirstResponder land after the sync, so
            // the becomeFirstResponder it triggers is a harmless no-op.
            DispatchQueue.main.async {
                Ghostty.moveFocus(to: surfaceView)
            }
        }

        // Becoming key races responder updates, so defer to let the
        // responder chain settle before syncSurfaceFocus() reads isKeyWindow.
        DispatchQueue.main.async { [weak self] in
            self?.syncSurfaceFocus()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        syncSurfaceFocus()
    }
}
