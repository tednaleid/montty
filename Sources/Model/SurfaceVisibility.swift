// ABOUTME: Pure policy deciding which terminal surfaces are on screen, so
// ABOUTME: libghostty can release GPU resources for the ones that are not.

import Foundation

enum SurfaceVisibility {
    /// Visibility for every surface across every tab, keyed by surface ID.
    ///
    /// A window shows only its active tab, so a surface is visible when its
    /// window is visible and it lives in the active tab. Every pane of the
    /// active tab is visible, focused or not.
    static func plan(
        tabs: [Tab],
        activeTabID: UUID?,
        windowIsVisible: Bool
    ) -> [UUID: Bool] {
        var plan: [UUID: Bool] = [:]
        for tab in tabs {
            let visible = windowIsVisible && tab.id == activeTabID
            for surfaceID in tab.allSurfaceIDs {
                plan[surfaceID] = visible
            }
        }
        return plan
    }
}
