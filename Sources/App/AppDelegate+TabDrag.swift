// ABOUTME: Watches a sidebar tab drag to its release, which AppKit does not report to SwiftUI,
// ABOUTME: and hands where it ended to the use case that decides whether it tears the tab off.

import AppKit

extension AppDelegate {
    /// A tab drag began in some window's sidebar. SwiftUI says when a drag
    /// starts and when it lands on a drop target, but not when it is released
    /// over nothing, so this polls the mouse button until it comes up.
    func tabDragBegan(_ tabID: UUID) {
        draggingTabID = tabID
        tabDragTimer?.invalidate()
        // `.common`, so it keeps firing while the drag session runs the loop in
        // its own tracking mode.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
            timer.invalidate()
            self?.tabDragTimer = nil
            self?.tabDragEnded(tabID, releasedAt: NSEvent.mouseLocation)
        }
        RunLoop.main.add(timer, forMode: .common)
        tabDragTimer = timer
    }

    /// The drag of `tabID` ended with the mouse at `point`, in screen
    /// coordinates. The use case decides whether that tears the tab off; a
    /// release over a window needs nothing from here, since a drop on a sidebar
    /// moved the tab through `moveTab` already.
    func tabDragEnded(_ tabID: UUID, releasedAt point: CGPoint) {
        draggingTabID = nil
        guard let source = registry.locate(tabID: tabID) else { return }

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
}
