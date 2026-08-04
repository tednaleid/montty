import Foundation
import Testing

struct SurfaceFocusTests {
    /// Adds a second pane to a tab and returns the new pane's surface ID.
    private func addSplit(to tab: Tab) -> UUID {
        let newLeafID = UUID()
        let newSurfaceID = UUID()
        tab.splitRoot = SplitTree.split(
            node: tab.splitRoot,
            leafID: tab.focusedLeafID!,
            orientation: .horizontal,
            newLeafID: newLeafID,
            newSurfaceID: newSurfaceID
        )
        return newSurfaceID
    }

    @Test func focusesTheActiveTabsFocusedPane() {
        let surface = UUID()
        let tab = Tab(surfaceID: surface)

        let plan = SurfaceFocus.plan(tabs: [tab], activeTabID: tab.id, windowIsKey: true)

        #expect(plan[surface] == true)
    }

    @Test func blursEverythingWhenWindowIsNotKey() {
        let surface = UUID()
        let tab = Tab(surfaceID: surface)

        let plan = SurfaceFocus.plan(tabs: [tab], activeTabID: tab.id, windowIsKey: false)

        #expect(plan[surface] == false)
    }

    @Test func blursEverythingWhenNoTabIsActive() {
        let surface = UUID()
        let tab = Tab(surfaceID: surface)

        let plan = SurfaceFocus.plan(tabs: [tab], activeTabID: nil, windowIsKey: true)

        #expect(plan[surface] == false)
    }

    @Test func blursTheFocusedPaneOfABackgroundTab() {
        let activeSurface = UUID()
        let backgroundSurface = UUID()
        let active = Tab(surfaceID: activeSurface)
        let background = Tab(surfaceID: backgroundSurface)

        let plan = SurfaceFocus.plan(
            tabs: [active, background], activeTabID: active.id, windowIsKey: true
        )

        #expect(plan[activeSurface] == true)
        #expect(plan[backgroundSurface] == false)
    }

    @Test func backgroundTabKeepsItsFocusedLeaf() {
        let active = Tab(surfaceID: UUID())
        let background = Tab(surfaceID: UUID())
        let originalLeafID = background.focusedLeafID

        _ = SurfaceFocus.plan(
            tabs: [active, background], activeTabID: active.id, windowIsKey: true
        )

        #expect(background.focusedLeafID == originalLeafID)
    }

    @Test func blursNonFocusedPanesInTheActiveTab() {
        let firstSurface = UUID()
        let tab = Tab(surfaceID: firstSurface)
        let secondSurface = addSplit(to: tab)

        let plan = SurfaceFocus.plan(tabs: [tab], activeTabID: tab.id, windowIsKey: true)

        #expect(plan[firstSurface] == true)
        #expect(plan[secondSurface] == false)
    }

    @Test func blursEveryPaneWhenTabHasNoFocusedLeaf() {
        let surface = UUID()
        let tab = Tab(surfaceID: surface)
        tab.focusedLeafID = nil

        let plan = SurfaceFocus.plan(tabs: [tab], activeTabID: tab.id, windowIsKey: true)

        #expect(plan[surface] == false)
    }

    @Test func includesEverySurfaceInEveryTab() {
        let activeSurface = UUID()
        let backgroundSurface = UUID()
        let active = Tab(surfaceID: activeSurface)
        let background = Tab(surfaceID: backgroundSurface)
        let activeSplit = addSplit(to: active)
        let backgroundSplit = addSplit(to: background)

        let plan = SurfaceFocus.plan(
            tabs: [active, background], activeTabID: active.id, windowIsKey: true
        )

        #expect(plan.count == 4)
        #expect(plan[activeSurface] != nil)
        #expect(plan[activeSplit] != nil)
        #expect(plan[backgroundSurface] != nil)
        #expect(plan[backgroundSplit] != nil)
    }

    @Test func focusesAtMostOneSurface() {
        let tabs = (0..<3).map { _ -> Tab in
            let tab = Tab(surfaceID: UUID())
            _ = addSplit(to: tab)
            return tab
        }

        let plan = SurfaceFocus.plan(
            tabs: tabs, activeTabID: tabs[1].id, windowIsKey: true
        )

        #expect(plan.values.filter { $0 }.count == 1)
    }
}
