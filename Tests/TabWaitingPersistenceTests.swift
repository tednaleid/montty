// ABOUTME: Verifies a Claude `waiting` state lasts until the user answers it by typing into the
// ABOUTME: pane, and that nothing else -- time, title changes -- ends it behind their back.

import Foundation
import Testing
@testable import montty_unit

struct TabWaitingPersistenceTests {
    private let monttyID = "mid-1"

    private func tab(with state: ActivityStatus.State?) -> (Tab, UUID) {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        tab.surfaceToMonttyID[surfaceID] = monttyID
        if let state {
            tab.activityStates[monttyID] = state
            if state == .waiting { tab.activityWaitingSince[monttyID] = Date() }
        }
        return (tab, surfaceID)
    }

    /// Waiting means waiting on the user, so typing is the answer. The state
    /// goes to idle: if Claude carries on, its next hook says working, and if the
    /// user interrupted it, no hook comes and idle is what it is.
    @Test func typingIntoAWaitingPaneEndsTheWait() {
        let (tab, surfaceID) = tab(with: .waiting)

        let changed = tab.clearWaitingOnUserInput(for: surfaceID)

        #expect(changed == true)
        #expect(tab.activityStates[monttyID] == .idle)
        #expect(tab.activityWaitingSince[monttyID] == nil)
    }

    @Test func typingLeavesAWorkingPaneAlone() {
        let (tab, surfaceID) = tab(with: .working)

        #expect(tab.clearWaitingOnUserInput(for: surfaceID) == false)
        #expect(tab.activityStates[monttyID] == .working)
    }

    @Test func typingLeavesAnIdlePaneAlone() {
        let (tab, surfaceID) = tab(with: .idle)

        #expect(tab.clearWaitingOnUserInput(for: surfaceID) == false)
        #expect(tab.activityStates[monttyID] == .idle)
    }

    @Test func typingIntoAPaneWithNoSessionChangesNothing() {
        let (tab, surfaceID) = tab(with: nil)

        #expect(tab.clearWaitingOnUserInput(for: surfaceID) == false)
        #expect(tab.activityStates.isEmpty)
    }

    @Test func typingIntoAnUnknownSurfaceChangesNothing() {
        let (tab, _) = tab(with: .waiting)

        #expect(tab.clearWaitingOnUserInput(for: UUID()) == false)
        #expect(tab.activityStates[monttyID] == .waiting)
    }

    /// A script that set `waiting` from the control CLI is waiting on the user
    /// just the same, and ends the same way.
    @Test func typingEndsAWaitTheControlCLISet() {
        let (tab, surfaceID) = tab(with: nil)
        var repoColorOverrides: [String: PaneTint] = [:]
        tab.applyControl(
            .setStatus(.waiting), surfaceID: surfaceID,
            repoColorOverrides: &repoColorOverrides
        )

        #expect(tab.clearWaitingOnUserInput(for: surfaceID) == true)
        #expect(tab.activityStates[monttyID] == .idle)
    }

    @Test func typingIntoOnePaneLeavesAnotherPanesWaitAlone() {
        let (tab, surfaceID) = tab(with: .waiting)
        tab.surfaceToMonttyID[UUID()] = "mid-2"
        tab.activityStates["mid-2"] = .waiting

        _ = tab.clearWaitingOnUserInput(for: surfaceID)

        #expect(tab.activityStates["mid-2"] == .waiting)
    }
}
