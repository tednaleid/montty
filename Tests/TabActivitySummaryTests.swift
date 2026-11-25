// ABOUTME: Verifies the one Claude status a tab shows when it holds several panes: the one
// ABOUTME: that most wants the user -- waiting, then idle, then working -- so none is hidden.

import Foundation
import Testing
@testable import montty_unit

struct TabActivitySummaryTests {
    @Test func waitingBeatsIdleAndWorking() {
        #expect(ActivityStatus.State.mostUrgent(of: [.idle, .working, .waiting]) == .waiting)
        #expect(ActivityStatus.State.mostUrgent(of: [.working, .waiting, .idle]) == .waiting)
    }

    /// A finished session is waiting on its next prompt, which wants the user
    /// more than one still busy on its own.
    @Test func idleBeatsWorking() {
        #expect(ActivityStatus.State.mostUrgent(of: [.working, .idle]) == .idle)
        #expect(ActivityStatus.State.mostUrgent(of: [.idle, .working]) == .idle)
    }

    @Test func workingIsTheLeastUrgent() {
        #expect(ActivityStatus.State.mostUrgent(of: [.working, .working]) == .working)
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
