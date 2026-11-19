// ABOUTME: Verifies moving a tab -- reordering within a window and transferring between
// ABOUTME: windows -- keeps the tab's surfaces alive and closes a window it empties.

import Foundation
import Testing
@testable import montty_unit

@Suite struct WindowUseCasesMoveTabTests {
    /// Windows holding `windowSurfaceCounts[i]` tabs each, already registered.
    private func makeUseCases(windowSurfaceCounts: [Int]) -> (WindowUseCases, [WindowModel]) {
        let useCases = WindowUseCases(registry: WindowRegistry())
        var windows: [WindowModel] = []
        for count in windowSurfaceCounts {
            let window = useCases.registry.add(WindowModel())
            for position in 0..<count {
                window.tabStore.append(tab: Tab(position: position, surfaceID: UUID()))
            }
            windows.append(window)
        }
        return (useCases, windows)
    }

    private let someFrame = WindowFrame(x: 0, y: 0, width: 1200, height: 800)

    @Test func movingATabToAnotherWindowTransfersItAndFocusesIt() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [2, 2])
        let moved = windows[0].tabStore.tabs[0]
        let stayed = windows[0].tabStore.tabs[1]
        let destinationTabs = windows[1].tabStore.tabs.map(\.id)

        let outcome = useCases.moveTab(id: moved.id, toWindow: windows[1].id, at: 1)

        #expect(windows[0].tabStore.tabs.map(\.id) == [stayed.id])
        #expect(windows[1].tabStore.tabs.map(\.id)
            == [destinationTabs[0], moved.id, destinationTabs[1]])
        #expect(windows[1].tabStore.activeTabID == moved.id)
        #expect(useCases.registry.keyWindowID == windows[1].id)
        #expect(outcome.raiseWindow == windows[1].id)
        #expect(outcome.save == true)
    }

    /// The surfaces go with the tab. Naming any of them for destruction would
    /// kill the shells the user just dragged.
    @Test func movingATabKeepsItsSurfaces() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [2, 1])
        let moved = windows[0].tabStore.tabs[0]
        let surfaceIDs = moved.allSurfaceIDs

        let outcome = useCases.moveTab(id: moved.id, toWindow: windows[1].id, at: 0)

        #expect(outcome.destroySurfaces.isEmpty)
        #expect(outcome.createSurfaces.isEmpty)
        #expect(useCases.registry.locate(surfaceID: surfaceIDs[0])?.window.id == windows[1].id)
    }

    @Test func movingTheOnlyTabOutOfAWindowClosesThatWindow() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [1, 1])
        let moved = windows[0].tabStore.tabs[0]

        let outcome = useCases.moveTab(id: moved.id, toWindow: windows[1].id, at: 1)

        #expect(outcome.closeWindows == [windows[0].id])
        #expect(outcome.quit == false)
    }

    /// The emptied window's close comes back through `windowDidClose`, which
    /// must find nothing of the moved tab left to destroy.
    @Test func theEmptiedWindowClosesWithoutDestroyingTheMovedSurfaces() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [1, 1])
        let moved = windows[0].tabStore.tabs[0]
        _ = useCases.moveTab(id: moved.id, toWindow: windows[1].id, at: 1)

        let outcome = useCases.windowDidClose(id: windows[0].id, frame: someFrame)

        #expect(outcome.destroySurfaces.isEmpty)
        #expect(outcome.quit == false)
        #expect(windows[1].tabStore.tabs.contains { $0.id == moved.id })
    }

    @Test func movingATabWithinItsWindowReorders() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [3])
        let ids = windows[0].tabStore.tabs.map(\.id)

        let outcome = useCases.moveTab(id: ids[0], toWindow: windows[0].id, at: 2)

        #expect(windows[0].tabStore.tabs.map(\.id) == [ids[1], ids[2], ids[0]])
        #expect(outcome.closeWindows.isEmpty)
        #expect(outcome.save == true)
    }

    @Test func movingATabToItsOwnPositionDoesNothing() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [3])
        let ids = windows[0].tabStore.tabs.map(\.id)

        let outcome = useCases.moveTab(id: ids[1], toWindow: windows[0].id, at: 1)

        #expect(windows[0].tabStore.tabs.map(\.id) == ids)
        #expect(outcome == WindowOutcome())
    }

    /// Dropping below the last row of another window's sidebar asks for an
    /// index past the end.
    @Test func movingToAnIndexPastTheEndAppends() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [2, 2])
        let moved = windows[0].tabStore.tabs[0]

        _ = useCases.moveTab(id: moved.id, toWindow: windows[1].id, at: 99)

        #expect(windows[1].tabStore.tabs.last?.id == moved.id)
    }

    @Test func movingAnUnknownTabDoesNothing() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [1, 1])

        let outcome = useCases.moveTab(id: UUID(), toWindow: windows[1].id, at: 0)

        #expect(outcome == WindowOutcome())
        #expect(windows[1].tabStore.tabs.count == 1)
    }

    /// A tab must never be detached with nowhere to land.
    @Test func movingToAnUnknownWindowLeavesTheTabWhereItWas() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [1, 1])
        let tab = windows[0].tabStore.tabs[0]

        let outcome = useCases.moveTab(id: tab.id, toWindow: UUID(), at: 0)

        #expect(outcome == WindowOutcome())
        #expect(windows[0].tabStore.tabs.map(\.id) == [tab.id])
    }

    @Test func aMovedTabsStateTravelsWithIt() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [2, 1])
        let moved = windows[0].tabStore.tabs[0]
        moved.name = "build"
        moved.colorOverride = PaneTint(stops: [.named(.red)])

        _ = useCases.moveTab(id: moved.id, toWindow: windows[1].id, at: 0)

        let landed = windows[1].tabStore.tabs[0]
        #expect(landed === moved)
        #expect(landed.name == "build")
        #expect(landed.colorOverride == PaneTint(stops: [.named(.red)]))
    }
}
