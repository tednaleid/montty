// ABOUTME: Keeps libghostty surface focus and visibility in step with each window's
// ABOUTME: key and occlusion state, which every window's controller forwards here.

import Cocoa
import GhosttyKit

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

    /// Push the focus policy out to every surface in every window. The only
    /// place montty calls `focusDidChange`, which updates both the Swift-side
    /// flag and the C-side `ghostty_surface_set_focus`.
    ///
    /// Each window's plan reads that window's own live `isKeyWindow`, not the
    /// registry's `keyWindowID` -- a window in the middle of resigning key is
    /// already reporting `isKeyWindow == false` even if `keyWindowID` was
    /// reassigned to another window earlier in the same call stack, so the
    /// resigning window's surfaces still blur correctly.
    ///
    /// Blurs run before focuses, across every window in one pass. libghostty
    /// writes the DEC mode 1004 reports in call order, and an outgoing surface
    /// must see its blur before any incoming surface sees its focus.
    ///
    /// Visibility changes at the same moments focus does -- tab switches, tabs
    /// and panes opening or closing, restore -- so this syncs it first.
    func syncSurfaceFocus() {
        syncSurfaceVisibility()
        var plan: [UUID: Bool] = [:]
        for windowModel in registry.windows {
            let isKey = controllers[windowModel.id]?.window.isKeyWindow ?? false
            plan.merge(SurfaceFocus.plan(
                tabs: windowModel.tabStore.tabs,
                activeTabID: windowModel.tabStore.activeTabID,
                windowIsKey: isKey
            )) { _, new in new }
        }
        for (surfaceID, focused) in plan where !focused {
            surfaces[surfaceID]?.focusDidChange(false)
        }
        for (surfaceID, focused) in plan where focused {
            surfaces[surfaceID]?.focusDidChange(true)
        }
    }

    /// Tell libghostty which surfaces are on screen, so it releases GPU
    /// resources for background tabs and hidden windows and rebuilds them on
    /// the next draw. libghostty ignores a call that repeats a surface's
    /// current state, so this pushes the whole plan every time.
    func syncSurfaceVisibility() {
        for windowModel in registry.windows {
            let windowIsVisible = controllers[windowModel.id]?.window
                .occlusionState.contains(.visible) ?? false
            let plan = SurfaceVisibility.plan(
                tabs: windowModel.tabStore.tabs,
                activeTabID: windowModel.tabStore.activeTabID,
                windowIsVisible: windowIsVisible
            )
            for (surfaceID, visible) in plan {
                guard let surface = surfaces[surfaceID]?.surface else { continue }
                ghostty_surface_set_occlusion(surface, visible)
            }
        }
    }
}
