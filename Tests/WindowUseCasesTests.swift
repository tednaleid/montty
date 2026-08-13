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
        _ = useCases.applicationShouldTerminate()

        let outcome = useCases.windowDidClose(id: windows[0].id)

        #expect(outcome.save == false)
        #expect(outcome.quit == false)
        #expect(outcome.destroySurfaces.count == 2)
    }

    @Test func terminatingSavesWhileWindowsRemain() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [1])

        let outcome = useCases.applicationShouldTerminate()

        #expect(outcome.save == true)
        #expect(useCases.isTerminating)
    }

    /// A quit that closed every window by hand has nothing left worth writing.
    @Test func terminatingWithNoWindowsDoesNotSave() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [])

        let outcome = useCases.applicationShouldTerminate()

        #expect(outcome.save == false)
    }

    @Test func closingAnUnknownWindowDoesNothing() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [1])

        let outcome = useCases.windowDidClose(id: UUID())

        #expect(outcome == WindowOutcome())
        #expect(useCases.registry.windows.count == 1)
    }

    @Test func closingByASurfaceTargetsThatSurfacesWindow() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [1, 1])
        useCases.registry.keyWindowID = windows[1].id
        let surfaceInFirst = windows[0].tabStore.tabs[0].allSurfaceIDs[0]

        let outcome = useCases.closeWindow(containing: surfaceInFirst)

        #expect(outcome.closeWindows == [windows[0].id])
    }

    /// A caller that cannot resolve a surface falls back to the window in front.
    @Test func closingWithNoSurfaceTargetsTheKeyWindow() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [1, 1])
        useCases.registry.keyWindowID = windows[1].id

        let outcome = useCases.closeWindow(containing: nil)

        #expect(outcome.closeWindows == [windows[1].id])
    }

    /// A surface id that was given but does not resolve must not fall back to
    /// closing the window in front -- that is the defect this decision exists
    /// to prevent, just with a stale id instead of a discarded one.
    @Test func closingWithAnUnknownSurfaceDoesNothing() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [1, 1])
        useCases.registry.keyWindowID = windows[1].id

        let outcome = useCases.closeWindow(containing: UUID())

        #expect(outcome == WindowOutcome())
        #expect(useCases.registry.windows.count == 2)
    }

    /// The shell turns `closeWindows` into NSWindow.close(), which comes back as
    /// windowDidClose. Naming the same window in both would loop.
    @Test func closingDoesNotTearDownDirectly() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [1, 1])

        let outcome = useCases.closeWindow(containing: nil)

        #expect(outcome.destroySurfaces.isEmpty)
        #expect(outcome.save == false)
        #expect(useCases.registry.windows.count == 2)
        _ = windows
    }

    @Test func aNewWindowIsRegisteredAndAsksForOneSurface() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [1])
        useCases.registry.keyWindowID = windows[0].id

        let outcome = useCases.newWindow(from: nil)

        #expect(useCases.registry.windows.count == 2)
        #expect(outcome.createWindows.count == 1)
        #expect(outcome.createSurfaces.count == 1)

        let created = outcome.createWindows[0]
        #expect(created.cascadeFrom == windows[0].id)
        #expect(outcome.raiseWindow == created.windowID)
        #expect(outcome.createSurfaces[0].windowID == created.windowID)
    }

    /// A new window opens where you were, the rule createTab already applies.
    @Test func aNewWindowInheritsTheGivenSurfacesDirectory() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [1])
        let surface = windows[0].tabStore.tabs[0].allSurfaceIDs[0]
        windows[0].tabStore.tabs[0].surfaceDirectories[surface] = "/Users/dev/work/alpha"

        let outcome = useCases.newWindow(from: surface)

        #expect(outcome.createSurfaces[0].workingDirectory == "/Users/dev/work/alpha")
    }

    /// Ghostty mints surface ids, so binding them to leaves is a second step.
    @Test func bindingSurfacesFillsInTheLeavesAndSaves() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [1])
        let outcome = useCases.newWindow(from: nil)
        let plan = outcome.createSurfaces[0]
        let surfaceID = UUID()

        let bound = useCases.surfacesCreated([plan.leafID: surfaceID])

        #expect(bound.save == true)
        let located = useCases.registry.locate(surfaceID: surfaceID)
        #expect(located?.window.id == plan.windowID)
        #expect(located?.tab.id == plan.tabID)
    }

    /// The shell registers a surface's monttyID under the minted id before
    /// reporting it back through surfacesCreated. Binding must not wipe that
    /// mapping out from under it.
    @Test func bindingSurfacesPreservesAMonttyIDTheShellAlreadyRecorded() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [1])
        let outcome = useCases.newWindow(from: nil)
        let plan = outcome.createSurfaces[0]
        let surfaceID = UUID()
        let tab = useCases.registry.window(id: plan.windowID)?
            .tabStore.tabs.first { $0.id == plan.tabID }
        tab?.surfaceToMonttyID[surfaceID] = "already-registered-montty-id"

        _ = useCases.surfacesCreated([plan.leafID: surfaceID])

        #expect(tab?.surfaceToMonttyID[surfaceID] == "already-registered-montty-id")
    }
}
