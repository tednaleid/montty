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
}
