// ABOUTME: Every window lifecycle and session decision, as functions that return
// ABOUTME: a WindowOutcome instead of touching AppKit, so they can be tested.

import Foundation

/// Owns the window registry and decides what should happen to it. It mutates
/// its own state and returns the AppKit work for the shell to run, but
/// performs no I/O and touches no AppKit.
final class WindowUseCases {
    let registry: WindowRegistry

    /// Latched once a quit is underway. `applicationShouldTerminate` saves the
    /// complete pre-close state, and AppKit then closes each window in turn --
    /// saving again on those would persist a mid-quit partial state over it.
    private(set) var isTerminating = false

    /// Latched once the shell reports the restored session fully assembled.
    /// Nothing may be saved before that: the shell finishes a restore in
    /// several steps, and a save taken partway through would write a session
    /// missing whatever the remaining steps put in place.
    private(set) var isRestored = false

    /// Where the last window to close stood, held for the save that follows it.
    /// Only ever set with nothing left open, which is the only session it is
    /// ever written into.
    private var lastClosedWindow: ClosedWindow?

    init(registry: WindowRegistry = WindowRegistry()) {
        self.registry = registry
    }

    /// AppKit is telling us a window closed. Closing a window is deliberate, so
    /// whatever remains afterward is what belongs on the next launch -- not what
    /// just closed. Nothing remaining is the one case that needs more than that:
    /// the tabs are gone by the user's choice, but where the window stood is
    /// not something they chose to throw away, so it outlives the close.
    ///
    /// `frame` is the window's on-screen frame, which only the shell can read.
    func windowDidClose(id: UUID, frame: WindowFrame) -> WindowOutcome {
        guard let window = registry.window(id: id) else { return WindowOutcome() }

        var outcome = WindowOutcome()
        outcome.destroySurfaces = window.tabStore.tabs.flatMap(\.allSurfaceIDs)
        registry.remove(id: id)

        guard !isTerminating else { return outcome }
        if registry.windows.isEmpty {
            lastClosedWindow = ClosedWindow(
                frame: frame,
                sidebarWidth: window.sidebarWidth,
                directory: window.directory
            )
        }
        outcome.save = true
        outcome.quit = registry.windows.isEmpty
        return outcome
    }

    /// A quit is starting. Must be called from
    /// `AppDelegate.applicationShouldTerminate(_:)`, before AppKit begins closing
    /// windows one at a time -- never from `applicationWillTerminate(_:)`, which
    /// runs after windows are already closing and would latch `isTerminating`
    /// too late to protect the pre-close save.
    func applicationShouldTerminate() -> WindowOutcome {
        isTerminating = true
        var outcome = WindowOutcome()
        outcome.save = !registry.windows.isEmpty
        return outcome
    }

    /// Open a window with one tab, inheriting the working directory of the
    /// surface it was opened from. The model joins the registry now; the
    /// outcome describes only the AppKit work.
    func newWindow(from surfaceID: UUID?) -> WindowOutcome {
        openWindow(
            model: WindowModel(),
            frame: nil,
            cascadeFrom: registry.keyWindow?.id,
            directory: surfaceID.flatMap(directory(ofSurface:))
        )
    }

    /// The window a launch with nothing to restore opens: where the last window
    /// to close stood, in the directory it was showing. A launch that has never
    /// had one opens wherever the shell puts it.
    private func newWindow(standingInFor closed: ClosedWindow?) -> WindowOutcome {
        guard let closed else { return newWindow(from: nil) }
        return openWindow(
            model: WindowModel(sidebarWidth: closed.sidebarWidth, frame: closed.frame),
            frame: closed.frame.isEmpty ? nil : closed.frame,
            cascadeFrom: nil,
            directory: closed.directory
        )
    }

    /// Registers a window holding one tab and names the AppKit work to build
    /// it. The one place a window is born outside a restore.
    private func openWindow(
        model: WindowModel,
        frame: WindowFrame?,
        cascadeFrom: UUID?,
        directory: String?
    ) -> WindowOutcome {
        let tab = Tab(position: 0)

        // `Tab.init` seeds one leaf with a placeholder surface id. Take that
        // leaf's id: `surfacesCreated` remaps it to the id Ghostty mints.
        guard let leaf = SplitTree.allLeaves(node: tab.splitRoot).first else {
            return WindowOutcome()
        }

        let window = registry.add(model)
        window.tabStore.append(tab: tab)
        window.tabStore.activeTabID = tab.id
        registry.keyWindowID = window.id

        var outcome = WindowOutcome()
        outcome.createWindows = [
            WindowPlan(windowID: window.id, frame: frame, cascadeFrom: cascadeFrom)
        ]
        outcome.createSurfaces = [
            SurfacePlan(
                leafID: leaf.id,
                windowID: window.id,
                tabID: tab.id,
                monttyID: UUID().uuidString,
                workingDirectory: directory
            )
        ]
        outcome.raiseWindow = window.id
        return outcome
    }

    /// Close the window owning `surfaceID`. `nil` means the caller has no
    /// surface to give, and the window in front closes. A surface id that was
    /// given but does not resolve to a window returns an inert outcome rather
    /// than closing whichever window happens to be in front. This only asks:
    /// the teardown happens when AppKit reports the close through
    /// `windowDidClose`.
    func closeWindow(containing surfaceID: UUID?) -> WindowOutcome {
        let target: WindowModel?
        if let surfaceID {
            target = registry.locate(surfaceID: surfaceID)?.window
        } else {
            target = registry.keyWindow
        }
        guard let target else { return WindowOutcome() }

        var outcome = WindowOutcome()
        outcome.closeWindows = [target.id]
        return outcome
    }

    /// Bind the surface ids Ghostty minted to the leaves that asked for them.
    ///
    /// Saves, so a surface opened after launch reaches disk without waiting for
    /// the next scheduled autosave -- but not while a restore is still in
    /// flight, where this runs before the shell has re-keyed the saved color
    /// overrides onto the ids Ghostty just minted.
    func surfacesCreated(_ bindings: [UUID: UUID]) -> WindowOutcome {
        for window in registry.windows {
            for tab in window.tabStore.tabs {
                tab.bindSurfaces(bindings)
            }
        }
        var outcome = WindowOutcome()
        outcome.save = isRestored
        return outcome
    }

    /// The shell has finished assembling the restored session. Opens saving for
    /// the rest of the process and takes the launch's first save, which is the
    /// earliest point where a written session is complete.
    func restoreCompleted() -> WindowOutcome {
        isRestored = true
        var outcome = WindowOutcome()
        outcome.save = true
        return outcome
    }

    /// The working directory recorded for a surface, used so a new window opens
    /// where you were.
    private func directory(ofSurface surfaceID: UUID) -> String? {
        registry.locate(surfaceID: surfaceID)?.tab.surfaceDirectories[surfaceID]
    }

    /// Rebuild the registry from a saved session. Windows join the registry
    /// now; the outcome names the AppKit work and the surfaces to create.
    func restore(_ snapshot: SessionSnapshot?) -> WindowOutcome {
        var outcome = WindowOutcome()
        if let snapshot {
            outcome.applySettings = SettingsUpdate(
                surfaceTintEnabled: snapshot.surfaceTintEnabled,
                repoColorOverrides: snapshot.repoColorOverrides
            )
        }

        let restorable = (snapshot?.windows ?? []).filter { !$0.tabs.isEmpty }
        guard !restorable.isEmpty else {
            var fresh = newWindow(standingInFor: snapshot?.lastClosedWindow)
            fresh.applySettings = outcome.applySettings
            return fresh
        }

        for saved in restorable {
            let window = registry.add(WindowModel(
                id: saved.windowID,
                sidebarWidth: saved.sidebarWidth,
                frame: saved.frame
            ))
            for savedTab in saved.tabs.sorted(by: { $0.position < $1.position }) {
                let tab = Tab(id: savedTab.tabID, name: savedTab.name, position: savedTab.position)
                tab.splitRoot = savedTab.splitLayout
                tab.focusedLeafID = savedTab.focusedLeafID
                tab.colorOverride = savedTab.colorOverride
                window.tabStore.append(tab: tab)

                for leaf in SplitTree.allLeaves(node: tab.splitRoot) {
                    outcome.createSurfaces.append(SurfacePlan(
                        leafID: leaf.id,
                        windowID: window.id,
                        tabID: tab.id,
                        monttyID: UUID().uuidString,
                        workingDirectory: savedTab.leafDirectories[leaf.id]
                    ))
                }
            }
            window.tabStore.activeTabID = saved.activeTabID ?? window.tabStore.tabs.first?.id
            outcome.createWindows.append(WindowPlan(
                windowID: window.id,
                frame: saved.frame.isEmpty ? nil : saved.frame,
                cascadeFrom: nil
            ))
        }

        let savedKey = snapshot?.keyWindowID
        registry.keyWindowID = savedKey.flatMap { registry.window(id: $0)?.id }
            ?? registry.windows.first?.id
        outcome.raiseWindow = registry.keyWindowID
        return outcome
    }

    /// The session montty would write right now. Takes the values only the
    /// shell can answer -- a window's on-screen frame and a surface's live
    /// working directory -- and the settings that live there.
    func snapshot(
        surfaceTintEnabled: Bool,
        repoColorOverrides: [String: PaneTint],
        frames: [UUID: WindowFrame],
        directories: [UUID: String]
    ) -> SessionSnapshot {
        var snapshot = SessionSnapshotBuilder.snapshot(
            windows: registry.windows,
            keyWindowID: registry.keyWindowID,
            surfaceTintEnabled: surfaceTintEnabled,
            repoColorOverrides: repoColorOverrides,
            environment: SessionEnvironment(
                frame: { frames[$0.id] ?? $0.frame },
                directory: { directories[$0] }
            )
        )
        snapshot.lastClosedWindow = lastClosedWindow
        return snapshot
    }
}
