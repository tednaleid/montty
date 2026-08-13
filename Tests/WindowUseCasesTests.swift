// ABOUTME: Verifies the window lifecycle decisions -- what to tear down, when to
// ABOUTME: save, and when to quit -- without launching the app.

import Foundation
import Testing
@testable import montty_unit

@Suite struct WindowUseCasesTests {
    /// A window holding `count` tabs, each with one surface, already registered.
    private func makeUseCases(windowSurfaceCounts: [Int]) -> (WindowUseCases, [WindowModel]) {
        let useCases = WindowUseCases(registry: WindowRegistry())
        var windows: [WindowModel] = []
        for count in windowSurfaceCounts {
            let window = useCases.registry.add(WindowModel())
            for position in 0..<count {
                let tab = Tab(position: position, surfaceID: UUID())
                window.tabStore.append(tab: tab)
            }
            windows.append(window)
        }
        return (useCases, windows)
    }

    @Test func closingTheLastWindowQuits() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [1])

        let outcome = useCases.windowDidClose(id: windows[0].id)

        #expect(outcome.quit == true)
        #expect(useCases.registry.windows.isEmpty)
    }

    @Test func closingOneOfTwoWindowsSavesWithoutQuitting() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [1, 1])

        let outcome = useCases.windowDidClose(id: windows[0].id)

        #expect(outcome.quit == false)
        #expect(outcome.save == true)
        #expect(useCases.registry.windows.map(\.id) == [windows[1].id])
    }

    /// Surfaces that outlive their window leak a shell, so the outcome must name
    /// every one of them.
    @Test func closingAWindowNamesEverySurfaceItOwned() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [3, 1])
        let expected = windows[0].tabStore.tabs.flatMap(\.allSurfaceIDs)
        #expect(expected.count == 3)

        let outcome = useCases.windowDidClose(id: windows[0].id)

        #expect(Set(outcome.destroySurfaces) == Set(expected))
    }

    /// A quit already saved the complete pre-close state, so the per-window
    /// closes AppKit runs while terminating must not save a partial one over it.
    @Test func aCloseDuringTerminationDoesNotSave() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [2])
        _ = useCases.applicationWillTerminate()

        let outcome = useCases.windowDidClose(id: windows[0].id)

        #expect(outcome.save == false)
        #expect(outcome.quit == false)
    }

    @Test func terminatingSavesWhileWindowsRemain() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [1])

        let outcome = useCases.applicationWillTerminate()

        #expect(outcome.save == true)
        #expect(useCases.isTerminating)
    }

    /// A quit that closed every window by hand has nothing left worth writing.
    @Test func terminatingWithNoWindowsDoesNotSave() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [])

        let outcome = useCases.applicationWillTerminate()

        #expect(outcome.save == false)
    }

    @Test func closingAnUnknownWindowDoesNothing() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [1])

        let outcome = useCases.windowDidClose(id: UUID())

        #expect(outcome == WindowOutcome())
        #expect(useCases.registry.windows.count == 1)
    }
}
