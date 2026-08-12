// ABOUTME: Keeps libghostty surface focus in step with each window's key state.
// ABOUTME: Every window's controller forwards its own key changes through here.

import Cocoa

extension AppDelegate {
    /// Takes the controller of the window that became key, so the responder
    /// repair below reads that window's tabs rather than looking up which
    /// window it must have been.
    func windowDidBecomeKey(_ controller: WindowController) {
        // If the window itself is first responder, no surface will accept
        // typing. Hand focus back to the active tab's pane.
        //
        // This guard only covers the window-holds-the-responder case. It does
        // NOT cover the more common repair: a surface that is still first
        // responder but whose `focused` flag went stale `false` across a
        // deactivate/reactivate cycle. There `firstResponder === window` is
        // false, so this branch is skipped entirely, and the fix happens
        // solely in the unconditional syncSurfaceFocus() call below.
        let window = controller.window
        if window.firstResponder === window,
           let surfaceID = controller.model.tabStore.activeTab?.focusedSurfaceID,
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

    /// Every window's plan is recomputed from its own live key state, so a
    /// window resigning key needs no argument to say which one it was.
    func windowDidResignKey() {
        syncSurfaceFocus()
    }
}
