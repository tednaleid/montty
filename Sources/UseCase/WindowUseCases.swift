// ABOUTME: Every window lifecycle and session decision, as functions that return
// ABOUTME: a WindowOutcome instead of touching AppKit, so they can be tested.

import Foundation

/// Owns the window registry and decides what should happen to it. Effect-free:
/// it mutates its own state and returns the AppKit work for the shell to run,
/// but performs no I/O and reaches no collaborator it was not constructed with.
final class WindowUseCases {
    let registry: WindowRegistry

    /// Latched once a quit is underway. `applicationShouldTerminate` saves the
    /// complete pre-close state, and AppKit then closes each window in turn --
    /// saving again on those would persist a mid-quit partial state over it.
    private(set) var isTerminating = false

    init(registry: WindowRegistry = WindowRegistry()) {
        self.registry = registry
    }

    /// AppKit is telling us a window closed. Closing a window is deliberate, so
    /// whatever remains afterward is what belongs on the next launch -- not what
    /// just closed.
    func windowDidClose(id: UUID) -> WindowOutcome {
        guard let window = registry.window(id: id) else { return WindowOutcome() }

        var outcome = WindowOutcome()
        outcome.destroySurfaces = window.tabStore.tabs.flatMap(\.allSurfaceIDs)
        registry.remove(id: id)

        guard !isTerminating else { return outcome }
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
        let cascadeFrom = registry.keyWindow?.id
        let window = registry.add(WindowModel())
        let tab = Tab(position: 0)
        window.tabStore.append(tab: tab)
        window.tabStore.activeTabID = tab.id
        registry.keyWindowID = window.id

        // `Tab.init` seeds one leaf with a placeholder surface id. Take that
        // leaf's id: `surfacesCreated` remaps it to the id Ghostty mints.
        guard let leaf = SplitTree.allLeaves(node: tab.splitRoot).first else {
            return WindowOutcome()
        }

        var outcome = WindowOutcome()
        outcome.createWindows = [
            WindowPlan(windowID: window.id, frame: nil, cascadeFrom: cascadeFrom)
        ]
        outcome.createSurfaces = [
            SurfacePlan(
                leafID: leaf.id,
                windowID: window.id,
                tabID: tab.id,
                monttyID: UUID().uuidString,
                workingDirectory: surfaceID.flatMap(directory(ofSurface:))
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
    func surfacesCreated(_ bindings: [UUID: UUID]) -> WindowOutcome {
        for window in registry.windows {
            for tab in window.tabStore.tabs {
                tab.bindSurfaces(bindings)
            }
        }
        var outcome = WindowOutcome()
        outcome.save = true
        return outcome
    }

    /// The working directory recorded for a surface, used so a new window opens
    /// where you were.
    private func directory(ofSurface surfaceID: UUID) -> String? {
        registry.locate(surfaceID: surfaceID)?.tab.surfaceDirectories[surfaceID]
    }
}
