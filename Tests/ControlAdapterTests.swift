// ABOUTME: Regression coverage for the adapter that runs a control command
// ABOUTME: against a Tab and writes the resulting state back onto it.

import Foundation
import Testing

@Suite struct ControlAdapterTests {
    private func tab(directory: String? = nil) -> (Tab, UUID) {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        tab.surfaceToMonttyID[surfaceID] = "M1"
        if let directory {
            tab.surfaceDirectories[surfaceID] = directory
        }
        return (tab, surfaceID)
    }

    private let git: (String) -> GitInfo? = { _ in
        GitInfo(
            repoName: "montty", branchName: "main",
            worktreeName: nil, repoPath: "/Users/ted/montty"
        )
    }

    @Test func menuStyleClearRemovesACLISetGradient() {
        let (tab, surfaceID) = tab()
        var repoColorOverrides: [String: PaneTint] = [:]
        let gradient = PaneTint(stops: [
            .named(.neutralBright), .hex(RGB(r: 0x1A, g: 0x7F, b: 0x37))
        ])

        tab.applyControl(
            .setColor(scope: .surface, tint: gradient),
            surfaceID: surfaceID, repoColorOverrides: &repoColorOverrides
        )
        #expect(tab.surfaceColorOverrides[surfaceID] == gradient)

        tab.applyControl(
            .clearColor(scope: .surface),
            surfaceID: surfaceID, repoColorOverrides: &repoColorOverrides
        )
        #expect(tab.surfaceColorOverrides[surfaceID] == nil)
    }

    @Test func nameWritesBackOntoTheTab() {
        let (tab, surfaceID) = tab()
        var repoColorOverrides: [String: PaneTint] = [:]

        let result = tab.applyControl(
            .setName("MR !123"),
            surfaceID: surfaceID, repoColorOverrides: &repoColorOverrides
        )

        #expect(result == .applied)
        #expect(tab.displayName == "MR !123")
    }

    @Test func repoColorWritesBackToTheAppWideOverrides() {
        let (tab, surfaceID) = tab(directory: "/Users/ted/montty")
        var repoColorOverrides: [String: PaneTint] = [:]
        let tint = PaneTint(stops: [.named(.cyan)])

        let result = tab.applyControl(
            .setColor(scope: .repo, tint: tint),
            surfaceID: surfaceID, repoColorOverrides: &repoColorOverrides,
            gitInfoProvider: git
        )

        #expect(result == .applied)
        #expect(repoColorOverrides["/Users/ted/montty"] == tint)
        #expect(tab.colorOverride == nil)
    }

    @Test func statusWritesBackOntoTheTab() {
        let (tab, surfaceID) = tab()
        var repoColorOverrides: [String: PaneTint] = [:]

        tab.applyControl(
            .setStatus(.waiting),
            surfaceID: surfaceID, repoColorOverrides: &repoColorOverrides
        )

        #expect(tab.activityStates["M1"] == .waiting)
        #expect(tab.activityWaitingSince["M1"] != nil)
    }

    @Test func aSurfaceWithNoMonttyIDIsRejected() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        var repoColorOverrides: [String: PaneTint] = [:]

        let result = tab.applyControl(
            .setName("nope"),
            surfaceID: surfaceID, repoColorOverrides: &repoColorOverrides
        )

        #expect(result == .rejected(.unknownSurface))
        #expect(tab.name.isEmpty)
    }
}
