// ABOUTME: Opens, closes, and tears down windows -- the one place a window is
// ABOUTME: created or its teardown decided between dropping it and quitting.

import Cocoa

extension AppDelegate {
    /// Run the AppKit work an outcome names. The one place a `WindowOutcome`
    /// becomes an effect.
    ///
    /// `save` runs before `quit` because a last-window close names both, and
    /// terminating first would lose the write.
    func apply(_ outcome: WindowOutcome) {
        if let settings = outcome.applySettings {
            surfaceTintEnabled = settings.surfaceTintEnabled
            repoColorOverrides = settings.repoColorOverrides
        }
        for plan in outcome.createWindows {
            makeWindow(plan)
        }
        createAndBindSurfaces(outcome.createSurfaces)
        for surfaceID in outcome.destroySurfaces {
            surfaceObservers.removeValue(forKey: surfaceID)
            surfaces.removeValue(forKey: surfaceID)
        }
        closeWindows(ids: outcome.closeWindows)
        if let id = outcome.raiseWindow {
            controllers[id]?.window.makeKeyAndOrderFront(nil)
            focusActiveSurface()
        }
        if outcome.save { saveSession() }
        if outcome.quit { NSApp.terminate(nil) }
    }

    /// Builds the NSWindow for a model the use cases have already registered,
    /// and places it: at the frame the plan carries, or else cascaded off the
    /// window it was opened from so the new one does not land exactly on top of
    /// it. Only this layer can read another window's on-screen frame or which
    /// displays are attached, which is why the plan names the source window
    /// rather than the offset.
    @discardableResult
    func makeWindow(_ plan: WindowPlan) -> WindowController? {
        guard let model = registry.window(id: plan.windowID) else { return nil }
        let controller = WindowController(
            model: model, ghostty: ghostty, appDelegate: self
        )
        controllers[model.id] = controller
        if let frame = plan.frame, !frame.isEmpty {
            // Clamped to an attached display: the screen a frame was saved on
            // may be gone, and a window placed there opens out of reach.
            let visible = NSScreen.screens.map(\.visibleFrame)
            controller.window.setFrame(
                frame.clamped(toVisible: visible).rect, display: true
            )
        } else if let source = plan.cascadeFrom,
                  let from = controllers[source]?.window.frame {
            controller.window.setFrameTopLeftPoint(
                NSPoint(x: from.origin.x + 24, y: from.origin.y + from.height - 24)
            )
        }
        controller.show()
        return controller
    }

    /// Creates the surfaces an outcome asked for, then hands the ids Ghostty
    /// minted back to the use cases, which bind them onto the leaves that
    /// asked for them. Focus and titles settle afterward, once every leaf
    /// points at a surface that exists: a surface is born with
    /// `focused == true`, so the tabs it displaced need blurring.
    ///
    /// The recursion is bounded. `surfacesCreated` names only a save, so the
    /// nested `apply` cannot ask for more surfaces.
    private func createAndBindSurfaces(_ plans: [SurfacePlan]) {
        guard !plans.isEmpty else { return }
        apply(useCases.surfacesCreated(createSurfaces(plans)))
        syncSurfaceFocus()
        for windowID in Set(plans.map(\.windowID)) {
            controllers[windowID]?.syncTitle()
        }
    }

    /// Creates one Ghostty surface per plan and reports which surface id each
    /// leaf ended up with. Ghostty mints those ids, so binding them to leaves
    /// is a second step the domain cannot take on its own.
    private func createSurfaces(_ plans: [SurfacePlan]) -> [UUID: UUID] {
        guard let app = ghostty.app else {
            Self.logger.error("createSurfaces: no Ghostty app, dropping \(plans.count) surface plan(s)")
            return [:]
        }
        var bindings: [UUID: UUID] = [:]
        for plan in plans {
            guard let tab = registry.window(id: plan.windowID)?
                .tabStore.tabs.first(where: { $0.id == plan.tabID }) else {
                Self.logger.error(
                    "createSurfaces: no tab \(plan.tabID) in window \(plan.windowID), dropping leaf \(plan.leafID)"
                )
                continue
            }
            var config = Ghostty.SurfaceConfiguration()
            config.workingDirectory = plan.workingDirectory
            config.environmentVariables["MONTTY_SURFACE_ID"] = plan.monttyID
            config.environmentVariables["MONTTY_PORT"] = String(Self.hookPort)
            config.environmentVariables["MONTTY_SOCKET"] = HookServer.socketPath
            config.environmentVariables["MONTTY_BIN"] = Self.binPath
            let surfaceView = Ghostty.SurfaceView(app, baseConfig: config)
            registerSurface(surfaceView, tab: tab, monttyID: plan.monttyID)
            // The directory the pane opened in, until its own shell reports a
            // pwd through the observer. A window opened from this pane before
            // that first report inherits this rather than nothing.
            if let directory = plan.workingDirectory {
                tab.surfaceDirectories[surfaceView.id] = directory
            }
            bindings[plan.leafID] = surfaceView.id
        }
        return bindings
    }

    /// Closes windows through the same `NSWindow.close()` path the red button
    /// uses, so `windowWillClose` is the one place that decides between
    /// dropping a window and quitting.
    ///
    /// Deferred a run loop turn: a close can be asked for by a Ghostty action
    /// on a surface that lives in the window being closed, and `.close()` can
    /// synchronously tear down that surface's view while it is still on the
    /// call stack that invoked us. Closing on the next turn lets that call
    /// stack unwind first.
    func closeWindows(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let windows = ids.compactMap { controllers[$0]?.window }
        DispatchQueue.main.async {
            for window in windows {
                window.close()
            }
        }
    }

    /// A window is going away, with intent -- closing a window is not the
    /// same as quitting, so whatever remains afterward (possibly nothing) is
    /// what belongs on the next launch, not what just closed. The use case
    /// drops it from the registry and decides whether to save and whether that
    /// was the last window standing; this runs the AppKit half.
    ///
    /// The controller is kept alive in `controllers` past the point where the
    /// registry forgets it, and only released on the next run loop turn --
    /// AppKit is still using the window and its delegate for the remainder of
    /// this close sequence.
    func windowWillClose(_ controller: WindowController) {
        // Read before the teardown below: the use cases keep this when it was
        // the last window standing, so the next launch opens where it stood.
        let frame = WindowFrame(controller.window.frame)
        // With isReleasedWhenClosed = false, AppKit does not tear the content
        // view hierarchy down on close the way it does when it owns the
        // window's release -- the SwiftUI tree, and the surfaces inside it,
        // would otherwise sit retained until the window itself deallocates,
        // which AppKit's own window tracking can delay indefinitely. Clearing
        // it here drops that reference immediately and deterministically.
        controller.window.contentView = nil
        apply(useCases.windowDidClose(id: controller.model.id, frame: frame))
        DispatchQueue.main.async { [weak self] in
            self?.controllers[controller.model.id] = nil
        }
    }

    /// Writes the session montty would restore from right now. Whether a save
    /// belongs here at all is the use cases' call; this only performs it.
    func saveSession() {
        sessionStore.save(snapshot: createSnapshot())
    }

    /// Opens a window with one tab, inheriting the working directory of the
    /// pane it was opened from.
    func newWindow() {
        apply(useCases.newWindow(from: focusedSurfaceID()))
    }

    /// Asks for the window owning `surfaceID` to close. A caller with no
    /// surface to name passes nil, and the window in front closes.
    func closeWindow(containing surfaceID: UUID?) {
        apply(useCases.closeWindow(containing: surfaceID))
    }

    /// Closes every open window, each one running through `windowWillClose`
    /// exactly as it would closing them by hand one at a time, so the last one
    /// quits.
    ///
    /// Driven from `registry.windows`, the authoritative list, not
    /// `controllers`: a just-closed window's controller is only released a
    /// run loop turn later (see `windowWillClose`), so `controllers` can
    /// still list one that closing again would be a no-op for, but
    /// shouldn't be asked to close a second time regardless.
    func closeAllWindows(_ sender: Any?) {
        closeWindows(ids: registry.windows.map(\.id))
    }
}
