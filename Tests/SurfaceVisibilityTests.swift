// ABOUTME: Tests the policy deciding which surfaces libghostty should render
// ABOUTME: and which it may release GPU resources for.

import Foundation
import Testing

struct SurfaceVisibilityTests {
    /// Adds a second pane to a tab and returns the new pane's surface ID.
    private func addSplit(to tab: Tab) -> UUID {
        let newSurfaceID = UUID()
        tab.splitRoot = SplitTree.split(
            node: tab.splitRoot,
            leafID: tab.focusedLeafID!,
            orientation: .horizontal,
            newLeafID: UUID(),
            newSurfaceID: newSurfaceID
        )
        return newSurfaceID
    }

    @Test func showsEveryPaneOfTheActiveTab() {
        let tab = Tab(surfaceID: UUID())
        let focused = tab.focusedSurfaceID!
        let unfocused = addSplit(to: tab)

        let plan = SurfaceVisibility.plan(tabs: [tab], activeTabID: tab.id, windowIsVisible: true)

        #expect(plan[focused] == true)
        #expect(plan[unfocused] == true)
    }

    @Test func hidesEveryPaneOfABackgroundTab() {
        let active = Tab(surfaceID: UUID())
        let background = Tab(surfaceID: UUID())
        let backgroundSplit = addSplit(to: background)

        let plan = SurfaceVisibility.plan(
            tabs: [active, background], activeTabID: active.id, windowIsVisible: true
        )

        #expect(plan[active.focusedSurfaceID!] == true)
        #expect(plan[background.focusedSurfaceID!] == false)
        #expect(plan[backgroundSplit] == false)
    }

    @Test func hidesEverythingWhenTheWindowIsNotVisible() {
        let tab = Tab(surfaceID: UUID())

        let plan = SurfaceVisibility.plan(tabs: [tab], activeTabID: tab.id, windowIsVisible: false)

        #expect(plan[tab.focusedSurfaceID!] == false)
    }

    @Test func hidesEverythingWhenNoTabIsActive() {
        let tab = Tab(surfaceID: UUID())

        let plan = SurfaceVisibility.plan(tabs: [tab], activeTabID: nil, windowIsVisible: true)

        #expect(plan[tab.focusedSurfaceID!] == false)
    }
}
