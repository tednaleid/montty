// ABOUTME: Verifies the one Claude status a tab shows when it holds several panes: the most
// ABOUTME: urgent of them, so a pane that needs the user is never hidden behind a quiet one.

import Foundation
import Testing
@testable import montty_unit

struct TabActivitySummaryTests {
    @Test func waitingBeatsWorkingAndIdle() {
        #expect(ActivityStatus.State.mostUrgent(of: [.idle, .working, .waiting]) == .waiting)
    }

    @Test func workingBeatsIdle() {
        #expect(ActivityStatus.State.mostUrgent(of: [.idle, .working]) == .working)
    }

    @Test func aLoneStateIsItself() {
        #expect(ActivityStatus.State.mostUrgent(of: [.idle]) == .idle)
    }

    @Test func noStatesIsNoStatus() {
        #expect(ActivityStatus.State.mostUrgent(of: []) == nil)
    }

    /// Two panes, one with a Claude session reporting in and one plain shell.
    private func twoPaneTab(
        states: [String: ActivityStatus.State]
    ) -> (TabProperties, [SurfaceLeaf]) {
        let first = SurfaceLeaf()
        let second = SurfaceLeaf()
        let root = SplitNode.split(SplitBranch(
            orientation: .horizontal, first: .leaf(first), second: .leaf(second)
        ))
        let props = TabProperties(
            name: "", autoName: "zsh", splitRoot: root, focusedLeafID: first.id,
            activityStates: states,
            surfaceToMonttyID: [first.surfaceID: "m1", second.surfaceID: "m2"]
        )
        return (props, [first, second])
    }

    @Test func aTabShowsTheMostUrgentStateAmongItsPanes() {
        let (props, _) = twoPaneTab(states: ["m1": .idle, "m2": .waiting])

        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })

        #expect(info.activity == .waiting)
    }

    @Test func aTabWithNoClaudeSessionShowsNoStatus() {
        let (props, _) = twoPaneTab(states: [:])

        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })

        #expect(info.activity == nil)
    }

    @Test func aTabIgnoresPanesThatNeverReportedAnything() {
        let (props, _) = twoPaneTab(states: ["m2": .working])

        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })

        #expect(info.activity == .working)
    }
}
