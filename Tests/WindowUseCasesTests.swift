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

    /// The defect this replaces: a file with no windows still carries its
    /// app-wide settings, and losing them destroys user data on the next save.
    @Test func restoringAFileWithNoWindowsStillRecoversSettings() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [])
        let saved = SessionSnapshot(
            surfaceTintEnabled: false,
            windows: [],
            keyWindowID: nil,
            repoColorOverrides: ["/Users/dev/work/alpha": PaneTint(stops: [.named(.blue)])]
        )

        let outcome = useCases.restore(saved)

        #expect(outcome.applySettings?.surfaceTintEnabled == false)
        #expect(outcome.applySettings?.repoColorOverrides.count == 1)
    }

    /// A quit that closed every window restores nothing, so the shell opens a
    /// fresh window the same way a first launch does.
    @Test func restoringAFileWithNoWindowsAsksForOneFreshWindow() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [])

        let outcome = useCases.restore(SessionSnapshot(
            surfaceTintEnabled: true, windows: [],
            keyWindowID: nil, repoColorOverrides: [:]
        ))

        #expect(outcome.createWindows.count == 1)
        #expect(outcome.createSurfaces.count == 1)
    }

    @Test func restoringTwoWindowsRebuildsBothWithTheirDirectories() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [])
        let leafOne = UUID(), leafTwo = UUID()
        let saved = SessionSnapshot(
            surfaceTintEnabled: true,
            windows: [
                windowSnapshot(leafID: leafOne, directory: "/Users/dev/work/alpha"),
                windowSnapshot(leafID: leafTwo, directory: "/Users/dev/work/beta")
            ],
            keyWindowID: nil,
            repoColorOverrides: [:]
        )

        let outcome = useCases.restore(saved)

        #expect(useCases.registry.windows.count == 2)
        #expect(outcome.createWindows.count == 2)
        #expect(Set(outcome.createSurfaces.map(\.workingDirectory)) ==
                ["/Users/dev/work/alpha", "/Users/dev/work/beta"])
    }

    /// A window whose tabs all vanished is not worth restoring.
    @Test func restoringSkipsWindowsWithNoTabs() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [])
        let saved = SessionSnapshot(
            surfaceTintEnabled: true,
            windows: [
                WindowSnapshot(
                    windowID: UUID(), frame: WindowFrame(x: 0, y: 0, width: 800, height: 600),
                    sidebarWidth: 200, activeTabID: nil, tabs: []
                ),
                windowSnapshot(leafID: UUID(), directory: nil)
            ],
            keyWindowID: nil, repoColorOverrides: [:]
        )

        let outcome = useCases.restore(saved)

        #expect(useCases.registry.windows.count == 1)
        #expect(outcome.createWindows.count == 1)
    }

    /// A fresh install has no session file at all -- distinct from a file that
    /// exists but names zero windows. Both open one fresh window, but only the
    /// latter has settings to recover.
    @Test func restoringWithNoSavedSessionAsksForOneFreshWindow() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [])

        let outcome = useCases.restore(nil)

        #expect(outcome.applySettings == nil)
        #expect(outcome.createWindows.count == 1)
        #expect(outcome.createSurfaces.count == 1)
    }

    /// A saved `keyWindowID` naming a window that was actually restored must
    /// be honored rather than defaulting to whichever window happened to be
    /// restored first.
    @Test func restoringHonorsTheSavedKeyWindowWhenItWasRestored() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [])
        let first = windowSnapshot(leafID: UUID(), directory: "/Users/dev/work/alpha")
        let second = windowSnapshot(leafID: UUID(), directory: "/Users/dev/work/beta")
        let saved = SessionSnapshot(
            surfaceTintEnabled: true,
            windows: [first, second],
            keyWindowID: second.windowID,
            repoColorOverrides: [:]
        )

        let outcome = useCases.restore(saved)

        #expect(useCases.registry.keyWindowID == second.windowID)
        #expect(outcome.raiseWindow == second.windowID)
    }

    /// A saved `keyWindowID` naming a window that was not restored -- because
    /// it was skipped for having no tabs, or belongs to a session that was
    /// hand-edited -- must not be adopted as-is; the registry needs a key
    /// window it actually holds.
    @Test func restoringFallsBackToAWindowItActuallyHasWhenTheSavedKeyWindowWasNotRestored() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [])
        let restored = windowSnapshot(leafID: UUID(), directory: "/Users/dev/work/alpha")
        let saved = SessionSnapshot(
            surfaceTintEnabled: true,
            windows: [restored],
            keyWindowID: UUID(),
            repoColorOverrides: [:]
        )

        let outcome = useCases.restore(saved)

        #expect(useCases.registry.keyWindowID == restored.windowID)
        #expect(outcome.raiseWindow == restored.windowID)
    }

    @Test func aSnapshotCarriesEveryOpenWindow() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [1, 1])

        let snapshot = useCases.snapshot(
            surfaceTintEnabled: false,
            repoColorOverrides: [:],
            frames: [:],
            directories: [:]
        )

        #expect(snapshot.windows.count == 2)
        #expect(snapshot.surfaceTintEnabled == false)
        #expect(Set(snapshot.windows.map(\.windowID)) == Set(windows.map(\.id)))
    }

    /// A window snapshot with one tab holding one leaf at `leafID`.
    private func windowSnapshot(leafID: UUID, directory: String?) -> WindowSnapshot {
        let tab = TabSnapshot(
            tabID: UUID(), name: "", position: 0, focusedLeafID: leafID,
            splitLayout: .leaf(SurfaceLeaf(id: leafID, surfaceID: UUID())),
            leafDirectories: directory.map { [leafID: $0] } ?? [:],
            leafColorOverrides: [:], colorOverride: nil
        )
        return WindowSnapshot(
            windowID: UUID(),
            frame: WindowFrame(x: 0, y: 0, width: 1200, height: 800),
            sidebarWidth: 200, activeTabID: tab.tabID, tabs: [tab]
        )
    }
}
