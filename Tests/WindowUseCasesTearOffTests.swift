// ABOUTME: Verifies tearing a tab off into its own window -- when a released drag counts
// ABOUTME: as a tear-off, where the new window opens, and that the tab keeps its surfaces.

import CoreGraphics
import Foundation
import Testing
@testable import montty_unit

@Suite struct WindowUseCasesTearOffTests {
    private let sourceFrame = WindowFrame(x: 100, y: 100, width: 1200, height: 800)
    /// Somewhere no window is.
    private let emptySpace = CGPoint(x: 1800, y: 600)
    /// One display, the visible area of a 1920x1080 screen.
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    /// A window with `tabCount` tabs, already registered, with a known frame.
    private func makeUseCases(tabCount: Int) -> (WindowUseCases, WindowModel) {
        let useCases = WindowUseCases(registry: WindowRegistry())
        let window = useCases.registry.add(WindowModel(sidebarWidth: 260, frame: sourceFrame))
        for position in 0..<tabCount {
            window.tabStore.append(tab: Tab(position: position, surfaceID: UUID()))
        }
        return (useCases, window)
    }

    private func frames(_ window: WindowModel) -> [UUID: WindowFrame] {
        [window.id: sourceFrame]
    }

    @Test func releasingOverEmptySpaceOpensTheTabInANewWindow() {
        let (useCases, source) = makeUseCases(tabCount: 2)
        let moved = source.tabStore.tabs[1]

        let outcome = useCases.tabDragEnded(
            id: moved.id, releasedAt: emptySpace, windowFrames: frames(source), screens: [screen]
        )

        #expect(useCases.registry.windows.count == 2)
        let created = useCases.registry.windows[1]
        #expect(created.tabStore.tabs.map(\.id) == [moved.id])
        #expect(created.tabStore.activeTabID == moved.id)
        #expect(source.tabStore.tabs.count == 1)
        #expect(useCases.registry.keyWindowID == created.id)
        #expect(outcome.createWindows.map(\.windowID) == [created.id])
        #expect(outcome.raiseWindow == created.id)
        #expect(outcome.save == true)
    }

    /// The tab moves whole, so its shells keep running: nothing is created or
    /// destroyed, and its surfaces now belong to the new window.
    @Test func theTornOffTabKeepsItsSurfaces() {
        let (useCases, source) = makeUseCases(tabCount: 2)
        let moved = source.tabStore.tabs[1]
        let surfaceID = moved.allSurfaceIDs[0]

        let outcome = useCases.tabDragEnded(
            id: moved.id, releasedAt: emptySpace, windowFrames: frames(source), screens: [screen]
        )

        #expect(outcome.createSurfaces.isEmpty)
        #expect(outcome.destroySurfaces.isEmpty)
        #expect(useCases.registry.locate(surfaceID: surfaceID)?.window.id
            == useCases.registry.windows[1].id)
    }

    /// The new window is the source's size with its title bar under the cursor,
    /// in screen coordinates where y grows upward.
    @Test func theNewWindowIsTheSourcesSizeWithItsTopLeftNearTheCursor() {
        let (useCases, source) = makeUseCases(tabCount: 2)

        let outcome = useCases.tabDragEnded(
            id: source.tabStore.tabs[1].id,
            releasedAt: CGPoint(x: 700, y: 900),
            windowFrames: frames(source), screens: [screen]
        )

        let frame = outcome.createWindows[0].frame
        #expect(frame == WindowFrame(x: 660, y: 900 + 12 - 800, width: 1200, height: 800))
        #expect(outcome.createWindows[0].cascadeFrom == nil)
    }

    /// A window wider or taller than the room left is pulled back onto the
    /// screen rather than hanging off its edge.
    @Test func theNewWindowIsPulledBackOntoTheScreen() {
        let (useCases, source) = makeUseCases(tabCount: 2)

        let outcome = useCases.tabDragEnded(
            id: source.tabStore.tabs[1].id,
            releasedAt: CGPoint(x: 1800, y: 200),
            windowFrames: frames(source), screens: [screen]
        )

        let frame = outcome.createWindows.first?.frame?.rect ?? .zero
        #expect(screen.contains(frame))
    }

    /// The cursor's screen decides, not whichever screen the window would
    /// overlap most: a window dropped near the bottom of one display must not
    /// open on the display beneath it.
    @Test func theNewWindowStaysOnTheScreenTheCursorIsOn() {
        let (useCases, source) = makeUseCases(tabCount: 2)
        let main = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let below = CGRect(x: 0, y: -1200, width: 1920, height: 1200)

        let outcome = useCases.tabDragEnded(
            id: source.tabStore.tabs[1].id,
            releasedAt: CGPoint(x: 50, y: 400),
            windowFrames: frames(source), screens: [below, main]
        )

        let frame = outcome.createWindows.first?.frame?.rect ?? .zero
        #expect(main.contains(frame))
    }

    @Test func aCursorOnASecondScreenPlacesTheWindowThere() {
        let (useCases, source) = makeUseCases(tabCount: 2)
        let main = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let right = CGRect(x: 1728, y: 0, width: 1920, height: 1080)

        let outcome = useCases.tabDragEnded(
            id: source.tabStore.tabs[1].id,
            releasedAt: CGPoint(x: 2000, y: 900),
            windowFrames: frames(source), screens: [main, right]
        )

        let frame = outcome.createWindows.first?.frame?.rect ?? .zero
        #expect(right.contains(frame))
    }

    @Test func theNewWindowKeepsTheSourcesSidebarWidth() {
        let (useCases, source) = makeUseCases(tabCount: 2)

        _ = useCases.tabDragEnded(
            id: source.tabStore.tabs[1].id, releasedAt: emptySpace, windowFrames: frames(source), screens: [screen]
        )

        #expect(useCases.registry.windows[1].sidebarWidth == 260)
    }

    /// A window with nothing but this tab would only be traded for a new one.
    @Test func aWindowsOnlyTabCannotBeTornOff() {
        let (useCases, source) = makeUseCases(tabCount: 1)

        let outcome = useCases.tabDragEnded(
            id: source.tabStore.tabs[0].id, releasedAt: emptySpace, windowFrames: frames(source), screens: [screen]
        )

        #expect(outcome == WindowOutcome())
        #expect(useCases.registry.windows.count == 1)
    }

    /// A release over any montty window is a drop on it, or a drag that went
    /// nowhere, but never a tear-off.
    @Test func releasingOverAnyWindowIsNotATearOff() {
        let (useCases, source) = makeUseCases(tabCount: 2)
        let other = useCases.registry.add(WindowModel(
            frame: WindowFrame(x: 1500, y: 200, width: 800, height: 600)
        ))
        let windowFrames = [source.id: sourceFrame, other.id: other.frame]

        let overSource = useCases.tabDragEnded(
            id: source.tabStore.tabs[1].id,
            releasedAt: CGPoint(x: 400, y: 400), windowFrames: windowFrames, screens: [screen]
        )
        let overOther = useCases.tabDragEnded(
            id: source.tabStore.tabs[1].id,
            releasedAt: CGPoint(x: 1800, y: 400), windowFrames: windowFrames, screens: [screen]
        )

        #expect(overSource == WindowOutcome())
        #expect(overOther == WindowOutcome())
        #expect(useCases.registry.windows.count == 2)
        #expect(source.tabStore.tabs.count == 2)
    }

    @Test func tearingOffAnUnknownTabDoesNothing() {
        let (useCases, source) = makeUseCases(tabCount: 2)

        let outcome = useCases.tabDragEnded(
            id: UUID(), releasedAt: emptySpace, windowFrames: frames(source), screens: [screen]
        )

        #expect(outcome == WindowOutcome())
        #expect(useCases.registry.windows.count == 1)
    }

    @Test func aTornOffTabsStateTravelsWithIt() {
        let (useCases, source) = makeUseCases(tabCount: 2)
        let moved = source.tabStore.tabs[1]
        moved.name = "build"

        _ = useCases.tabDragEnded(
            id: moved.id, releasedAt: emptySpace, windowFrames: frames(source), screens: [screen]
        )

        #expect(useCases.registry.windows[1].tabStore.tabs[0] === moved)
        #expect(moved.name == "build")
    }

    /// Closing the window it left behind must not take the moved tab's surfaces
    /// with it.
    @Test func closingTheSourceWindowAfterwardsDestroysNothingOfTheTornOffTab() {
        let (useCases, source) = makeUseCases(tabCount: 2)
        let moved = source.tabStore.tabs[1]
        _ = useCases.tabDragEnded(
            id: moved.id, releasedAt: emptySpace, windowFrames: frames(source), screens: [screen]
        )

        let outcome = useCases.windowDidClose(id: source.id, frame: sourceFrame)

        #expect(Set(outcome.destroySurfaces).isDisjoint(with: Set(moved.allSurfaceIDs)))
    }
}
