// ABOUTME: Pure policy deciding which terminal surface libghostty should treat as
// ABOUTME: focused, given tab state and whether the montty window is key.

import Foundation

enum SurfaceFocus {
    /// Focus state for every surface across every tab, keyed by surface ID.
    ///
    /// A surface is focused only when the window is key, it lives in the active
    /// tab, and it is that tab's focused leaf. Every other surface is blurred,
    /// including the focused leaf of a background tab. Background tabs keep
    /// their `focusedLeafID` so the minimap and re-activation still work.
    static func plan(
        tabs: [Tab],
        activeTabID: UUID?,
        windowIsKey: Bool
    ) -> [UUID: Bool] {
        var plan: [UUID: Bool] = [:]
        for tab in tabs {
            let tabCanHoldFocus = windowIsKey && tab.id == activeTabID
            for leaf in SplitTree.allLeaves(node: tab.splitRoot) {
                plan[leaf.surfaceID] = tabCanHoldFocus && leaf.id == tab.focusedLeafID
            }
        }
        return plan
    }
}
