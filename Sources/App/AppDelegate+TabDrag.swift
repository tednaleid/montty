// ABOUTME: Hands the end of a sidebar tab drag, and a request to move a tab to a window of
// ABOUTME: its own, to the use cases that decide whether a new window opens.

import AppKit

extension AppDelegate {
    /// The drag of `tabID` ended with the mouse at `point`, in screen
    /// coordinates, or was cancelled when `point` is nil. The use case decides
    /// whether that tears the tab off; a release over a window needs nothing
    /// from here, since a drop on a sidebar moves the tab through `moveTab`.
    func tabDragEnded(_ tabID: UUID, releasedAt point: CGPoint?) {
        draggingTabID = nil
        guard let point, let source = registry.locate(tabID: tabID) else { return }

        // Only windows a person can see: a closing one is kept in `controllers`
        // for a run loop turn, and a minimized one is not under the cursor.
        var frames: [UUID: WindowFrame] = [:]
        for (id, controller) in controllers where registry.window(id: id) != nil
            && controller.window.isVisible {
            frames[id] = WindowFrame(controller.window.frame)
        }
        apply(useCases.tabDragEnded(
            id: tabID, releasedAt: point, windowFrames: frames,
            screens: NSScreen.screens.map(\.visibleFrame)
        ))
        syncSurfaceFocus()
        controllers[source.id]?.syncTitle()
    }

    /// Moves `tabID` into a window of its own, placed as Cmd-N would place one.
    func moveTabToNewWindow(id tabID: UUID) {
        guard let source = registry.locate(tabID: tabID) else { return }
        apply(useCases.moveTabToNewWindow(id: tabID))
        syncSurfaceFocus()
        controllers[source.id]?.syncTitle()
    }
}
