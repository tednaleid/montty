// ABOUTME: Opens, closes, and tears down windows -- the one place a window is
// ABOUTME: created or its teardown decided between dropping it and quitting.

import Cocoa

extension AppDelegate {
    /// Builds a window, registers it, and returns its controller. Every window
    /// in the process is created here.
    @discardableResult
    func makeWindow(_ model: WindowModel = WindowModel()) -> WindowController {
        registry.add(model)
        let controller = WindowController(
            model: model, ghostty: ghostty, appDelegate: self
        )
        controllers[model.id] = controller
        return controller
    }

    /// A window is going away, with intent -- closing a window is not the
    /// same as quitting, so whatever remains afterward (possibly nothing) is
    /// what belongs on the next launch, not what just closed. Tears down its
    /// surfaces, drops it from the registry, saves the survivors, then quits
    /// only if that was the last window standing.
    ///
    /// The controller is kept alive in `controllers` past the point where the
    /// registry forgets it, and only released on the next run loop turn --
    /// AppKit is still using the window and its delegate for the remainder of
    /// this close sequence.
    func windowWillClose(_ controller: WindowController) {
        for tab in controller.model.tabStore.tabs {
            for surfaceID in tab.allSurfaceIDs {
                surfaceObservers.removeValue(forKey: surfaceID)
                surfaces.removeValue(forKey: surfaceID)
            }
        }
        // With isReleasedWhenClosed = false, AppKit does not tear the content
        // view hierarchy down on close the way it does when it owns the
        // window's release -- the SwiftUI tree, and the surfaces inside it,
        // would otherwise sit retained until the window itself deallocates,
        // which AppKit's own window tracking can delay indefinitely. Clearing
        // it here drops that reference immediately and deterministically.
        controller.window.contentView = nil
        registry.remove(id: controller.model.id)
        saveAfterWindowClose()
        if registry.windows.isEmpty {
            NSApp.terminate(nil)
        }
        DispatchQueue.main.async { [weak self] in
            self?.controllers[controller.model.id] = nil
        }
    }

    /// Saves whatever remains once a window is gone, unless an app-wide quit
    /// already covered it.
    ///
    /// Two guards, not one. `isTerminating` is the primary one: skipped
    /// entirely once a quit is underway, since `applicationShouldTerminate`
    /// already saved the complete pre-close state before AppKit started
    /// closing windows one by one as part of terminating, and saving again
    /// here on each of those would persist a mid-quit partial state instead.
    ///
    /// `lastQuitSnapshot` is the belt-and-braces second guard: even if
    /// `isTerminating` were somehow wrong, this refuses to let an empty
    /// snapshot -- the correct result only when a window closed by hand
    /// brings the count to zero outside any quit -- overwrite the complete
    /// state a real quit already captured. `lastQuitSnapshot` is `nil` for
    /// the entire organic close-to-zero sequence, since
    /// `applicationShouldTerminate` never runs until this function's own
    /// `NSApp.terminate(nil)` call below fires it, which happens after this
    /// save has already run.
    private func saveAfterWindowClose() {
        guard !isTerminating else { return }
        let snapshot = createSnapshot()
        guard !(snapshot.windows.isEmpty && lastQuitSnapshot != nil) else { return }
        sessionStore.save(snapshot: snapshot)
    }

    /// Opens a window with one tab, cascaded from the window in front so the new
    /// one does not land exactly on top of it.
    func newWindow() {
        let keyFrame = keyController?.window.frame
        let controller = makeWindow()
        if let keyFrame {
            controller.window.setFrameTopLeftPoint(
                NSPoint(x: keyFrame.origin.x + 24, y: keyFrame.origin.y + keyFrame.height - 24)
            )
        }
        registry.keyWindowID = controller.model.id
        createTab()
        controller.show()
        focusActiveSurface()
    }

    /// Closes the key window through the same `NSWindow.close()` path the red
    /// button uses, so `windowWillClose` is the one place that decides between
    /// dropping a window and quitting.
    ///
    /// Deferred a run loop turn: this runs from a Ghostty action on a surface
    /// that lives in the window being closed, and `.close()` can synchronously
    /// tear down that surface's view while it is still on the call stack that
    /// invoked us. Closing on the next turn lets that call stack unwind first.
    func closeWindow() {
        let windowToClose = keyController?.window
        DispatchQueue.main.async {
            windowToClose?.close()
        }
    }

    /// Closes every open window through the same `NSWindow.close()` path a
    /// single window close uses, so `windowWillClose` handles each one's
    /// teardown and save, and the last one quits, exactly as it would closing
    /// them by hand one at a time.
    ///
    /// Driven from `registry.windows`, the authoritative list, not
    /// `controllers`: a just-closed window's controller is only released a
    /// run loop turn later (see `windowWillClose`), so `controllers` can
    /// still list one that closing again would be a no-op for, but
    /// shouldn't be asked to close a second time regardless.
    ///
    /// Deferred a run loop turn for the same reason `closeWindow()` is: this
    /// can run from a Ghostty action on a surface in one of the windows being
    /// closed, and closing synchronously risks tearing down that surface's
    /// view while it is still on the call stack that invoked us.
    func closeAllWindows(_ sender: Any?) {
        let windowsToClose = registry.windows.compactMap { controllers[$0.id]?.window }
        DispatchQueue.main.async {
            for window in windowsToClose {
                window.close()
            }
        }
    }
}
