import Foundation
import Testing

@Suite struct ControlServiceTests {
    private let surfaceID = UUID()
    private let leafID = UUID()
    private let tabID = UUID()

    private func ref(directory: String? = "/Users/ted/montty") -> SurfaceRef {
        SurfaceRef(
            monttyID: "M1", surfaceID: surfaceID, leafID: leafID,
            tabID: tabID, directory: directory
        )
    }

    private func state() -> ControlState {
        ControlState(
            tabName: "", autoName: "montty/", surfaceColorOverrides: [:],
            tabColorOverride: nil, repoColorOverrides: [:],
            activityStates: [:], activityWaitingSince: [:]
        )
    }

    private let git: (String) -> GitInfo? = { _ in
        GitInfo(
            repoName: "montty", branchName: "main",
            worktreeName: nil, repoPath: "/Users/ted/montty"
        )
    }

    @Test func setsSurfaceColor() {
        var subject = state()
        let tint = PaneTint(stops: [.hex(RGB(r: 1, g: 2, b: 3))])
        let result = ControlService.apply(
            .setColor(scope: .surface, tint: tint),
            target: ref(), to: &subject, gitInfoProvider: git
        )
        #expect(result == .applied)
        #expect(subject.surfaceColorOverrides[surfaceID] == tint)
    }

    @Test func setsTabColorAndClearsIt() {
        var subject = state()
        let tint = PaneTint(stops: [.named(.green)])
        _ = ControlService.apply(
            .setColor(scope: .tab, tint: tint),
            target: ref(), to: &subject, gitInfoProvider: git
        )
        #expect(subject.tabColorOverride == tint)

        _ = ControlService.apply(
            .clearColor(scope: .tab),
            target: ref(), to: &subject, gitInfoProvider: git
        )
        #expect(subject.tabColorOverride == nil)
    }

    @Test func setsRepoColorUnderTheRepoIdentity() {
        var subject = state()
        let tint = PaneTint(stops: [.named(.cyan)])
        let result = ControlService.apply(
            .setColor(scope: .repo, tint: tint),
            target: ref(), to: &subject, gitInfoProvider: git
        )
        #expect(result == .applied)
        #expect(subject.repoColorOverrides["/Users/ted/montty"] == tint)
    }

    @Test func rejectsRepoScopeOutsideAGitRepo() {
        var subject = state()
        let result = ControlService.apply(
            .setColor(scope: .repo, tint: PaneTint(stops: [.named(.cyan)])),
            target: ref(directory: "/tmp"), to: &subject,
            gitInfoProvider: { _ in nil }
        )
        #expect(result == .rejected(.notInRepo))
        #expect(subject.repoColorOverrides.isEmpty)
    }

    @Test func setsAndClearsTabName() {
        var subject = state()
        _ = ControlService.apply(
            .setName("MR !123"), target: ref(), to: &subject, gitInfoProvider: git
        )
        #expect(subject.tabName == "MR !123")

        _ = ControlService.apply(
            .clearName, target: ref(), to: &subject, gitInfoProvider: git
        )
        #expect(subject.tabName == "")
    }

    @Test func setsActivityStatusThroughTheHookStateMachine() {
        var subject = state()
        _ = ControlService.apply(
            .setStatus(.waiting), target: ref(), to: &subject, gitInfoProvider: git
        )
        #expect(subject.activityStates["M1"] == .waiting)
        #expect(subject.activityWaitingSince["M1"] != nil)

        _ = ControlService.apply(
            .setStatus(.working), target: ref(), to: &subject, gitInfoProvider: git
        )
        #expect(subject.activityStates["M1"] == .working)
        #expect(subject.activityWaitingSince["M1"] == nil)
    }

    @Test func clearingStatusRemovesTheEntry() {
        var subject = state()
        _ = ControlService.apply(
            .setStatus(.working), target: ref(), to: &subject, gitInfoProvider: git
        )
        _ = ControlService.apply(
            .setStatus(nil), target: ref(), to: &subject, gitInfoProvider: git
        )
        #expect(subject.activityStates["M1"] == nil)
    }

    @Test func infoReportsScopesAndLeavesStateUntouched() {
        var subject = state()
        subject.surfaceColorOverrides[surfaceID] = PaneTint(stops: [.named(.red)])
        subject.repoColorOverrides["/Users/ted/montty"] = PaneTint(stops: [.named(.cyan)])
        let before = subject

        let result = ControlService.apply(
            .info, target: ref(), to: &subject, gitInfoProvider: git
        )

        guard case .read(let info) = result else {
            Issue.record("expected a read result")
            return
        }
        #expect(info.surfaceID == "M1")
        #expect(info.scopes.surface?.stops == ["red"])
        #expect(info.scopes.tab == nil)
        #expect(info.scopes.repo?.identity == "/Users/ted/montty")
        #expect(info.effective?.stops == ["red"])
        #expect(info.tabName == "montty/")
        #expect(info.tabNameIsOverride == false)
        #expect(subject.surfaceColorOverrides == before.surfaceColorOverrides)
        #expect(subject.tabName == before.tabName)
    }

    @Test func infoReportsTheOverriddenNameWhenOneIsSet() {
        var subject = state()
        subject.tabName = "MR !123"
        let result = ControlService.apply(
            .info, target: ref(), to: &subject, gitInfoProvider: git
        )
        guard case .read(let info) = result else {
            Issue.record("expected a read result")
            return
        }
        #expect(info.tabName == "MR !123")
        #expect(info.tabNameIsOverride)
    }
}
