// ABOUTME: Verifies opening a tab on a pane's behalf: which window it lands in, that it stays
// ABOUTME: in the background unless asked, where it starts, and what it launches.

import Foundation
import Testing
@testable import montty_unit

@Suite struct WindowUseCasesOpenTabTests {
    /// The two windows and the pane that asks.
    private struct Windows {
        let first: WindowModel
        let second: WindowModel
        let caller: String
    }

    /// Two windows of one tab each. The caller is in the second, which is not
    /// the key window, so a tab landing in the wrong window shows.
    private func makeUseCases() -> (WindowUseCases, Windows) {
        let useCases = WindowUseCases(registry: WindowRegistry())
        let first = useCases.registry.add(WindowModel())
        let second = useCases.registry.add(WindowModel())
        first.tabStore.append(tab: Tab(position: 0, surfaceID: UUID()))
        let caller = Tab(position: 0, surfaceID: UUID())
        second.tabStore.append(tab: caller)
        let surfaceID = caller.allSurfaceIDs[0]
        caller.surfaceToMonttyID[surfaceID] = "CALLER"
        caller.surfaceDirectories[surfaceID] = "/Users/dev/work/alpha"
        useCases.registry.keyWindowID = first.id
        return (useCases, Windows(first: first, second: second, caller: "CALLER"))
    }

    @Test func theTabOpensInTheCallersWindowNotTheKeyWindow() {
        let (useCases, windows) = makeUseCases()

        _ = useCases.openTab(NewTab(), fromMonttyID: windows.caller)

        #expect(windows.first.tabStore.tabs.count == 1)
        #expect(windows.second.tabStore.tabs.count == 2)
    }

    @Test func theTabIsAppendedWithAContiguousPosition() {
        let (useCases, windows) = makeUseCases()

        _ = useCases.openTab(NewTab(), fromMonttyID: windows.caller)
        _ = useCases.openTab(NewTab(), fromMonttyID: windows.caller)

        #expect(windows.second.tabStore.tabs.map(\.position) == [0, 1, 2])
    }

    /// A session that spawns tabs must not pull the user off the one they are in.
    @Test func theTabOpensInTheBackgroundByDefault() {
        let (useCases, windows) = makeUseCases()
        let before = windows.second.tabStore.activeTabID

        let outcome = useCases.openTab(NewTab(), fromMonttyID: windows.caller)

        #expect(windows.second.tabStore.activeTabID == before)
        #expect(outcome.raiseWindow == nil)
        #expect(useCases.registry.keyWindowID != windows.second.id)
    }

    @Test func focusSelectsTheNewTab() {
        let (useCases, windows) = makeUseCases()

        _ = useCases.openTab(NewTab(focus: true), fromMonttyID: windows.caller)

        #expect(windows.second.tabStore.activeTabID == windows.second.tabStore.tabs.last?.id)
    }

    @Test func theTabTakesTheRequestedName() {
        let (useCases, windows) = makeUseCases()

        _ = useCases.openTab(NewTab(name: "review"), fromMonttyID: windows.caller)

        #expect(windows.second.tabStore.tabs.last?.name == "review")
    }

    @Test func itAsksForOneSurfaceBoundToTheNewTab() {
        let (useCases, windows) = makeUseCases()

        let outcome = useCases.openTab(NewTab(), fromMonttyID: windows.caller)

        let tab = windows.second.tabStore.tabs.last
        #expect(outcome.createSurfaces.count == 1)
        #expect(outcome.createSurfaces.first?.tabID == tab?.id)
        #expect(outcome.createSurfaces.first?.windowID == windows.second.id)
        let leafID = tab.flatMap { SplitTree.allLeaves(node: $0.splitRoot).first?.id }
        #expect(outcome.createSurfaces.first?.leafID == leafID)
        #expect(outcome.createSurfaces.first?.runsLaunch == false)
    }

    @Test func eachTabGetsItsOwnMonttyID() {
        let (useCases, windows) = makeUseCases()

        let one = useCases.openTab(NewTab(), fromMonttyID: windows.caller).createSurfaces[0].monttyID
        let two = useCases.openTab(NewTab(), fromMonttyID: windows.caller).createSurfaces[0].monttyID

        #expect(one != two)
        #expect(one != windows.caller)
    }

    @Test func theTabStartsWhereTheCallerWas() {
        let (useCases, windows) = makeUseCases()

        let outcome = useCases.openTab(NewTab(), fromMonttyID: windows.caller)

        #expect(outcome.createSurfaces[0].workingDirectory == "/Users/dev/work/alpha")
    }

    @Test func anExplicitDirectoryWins() {
        let (useCases, windows) = makeUseCases()

        let outcome = useCases.openTab(NewTab(directory: "/opt/other"), fromMonttyID: windows.caller)

        #expect(outcome.createSurfaces[0].workingDirectory == "/opt/other")
    }

    @Test func aTabWithACommandRunsTheLaunchLineAndKeepsTheCommandForIt() {
        let (useCases, windows) = makeUseCases()
        let command = ["claude", "fix\nthe build"]

        let outcome = useCases.openTab(NewTab(command: command), fromMonttyID: windows.caller)

        let plan = outcome.createSurfaces[0]
        #expect(plan.runsLaunch == true)
        #expect(useCases.takeLaunch(monttyID: plan.monttyID) == command)
    }

    @Test func theKeptCommandIsHandedOverOnce() {
        let (useCases, windows) = makeUseCases()
        let outcome = useCases.openTab(NewTab(command: ["htop"]), fromMonttyID: windows.caller)
        let monttyID = outcome.createSurfaces[0].monttyID

        #expect(useCases.takeLaunch(monttyID: monttyID) == ["htop"])
        #expect(useCases.takeLaunch(monttyID: monttyID) == nil)
    }

    @Test func aSurfaceOpenedWithoutACommandHasNoneToTake() {
        let (useCases, windows) = makeUseCases()
        let outcome = useCases.openTab(NewTab(), fromMonttyID: windows.caller)

        #expect(useCases.takeLaunch(monttyID: outcome.createSurfaces[0].monttyID) == nil)
        #expect(useCases.takeLaunch(monttyID: windows.caller) == nil)
    }

    @Test func aRequestFromAnUnknownPaneChangesNothing() {
        let (useCases, windows) = makeUseCases()

        let outcome = useCases.openTab(NewTab(name: "x"), fromMonttyID: "NOBODY")

        #expect(outcome == WindowOutcome())
        #expect(windows.first.tabStore.tabs.count == 1)
        #expect(windows.second.tabStore.tabs.count == 1)
    }
}
