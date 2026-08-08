// ABOUTME: Tests the surface > tab > repo > git signature precedence chain
// ABOUTME: that TabColor.resolvedPaneTint and Tab.effectivePaneTint resolve through.

import Foundation
import Testing
@testable import montty_unit

@Suite struct PaneTintPrecedenceTests {
    private let surfaceTint = PaneTint(stops: [.hex(RGB(r: 0x1A, g: 0x7F, b: 0x37))])
    private let tabTint = PaneTint(stops: [.named(.blue), .named(.red)])

    @Test func surfaceOverrideBeatsEverything() {
        let tint = TabColor.resolvedPaneTint(
            surfaceOverride: surfaceTint,
            tabColorOverride: tabTint,
            surfaceDirectory: "/tmp",
            repoColorOverrides: [:]
        )
        #expect(tint == surfaceTint)
    }

    @Test func tabOverrideBeatsRepoAndGit() {
        let tint = TabColor.resolvedPaneTint(
            surfaceOverride: nil,
            tabColorOverride: tabTint,
            surfaceDirectory: "/tmp",
            repoColorOverrides: ["/tmp": PaneTint(stops: [.named(.cyan)])]
        )
        #expect(tint == tabTint)
    }

    @Test func tabOverrideKeepsItsGradient() {
        let tint = TabColor.resolvedPaneTint(
            surfaceOverride: nil,
            tabColorOverride: tabTint,
            surfaceDirectory: nil,
            repoColorOverrides: [:]
        )
        #expect(tint?.stops.count == 2)
        #expect(tint?.isGradient == true)
    }

    @Test func repoOverrideWinsOverGitSignature() {
        let info = GitInfo(
            repoName: "montty", branchName: "main",
            worktreeName: nil, repoPath: "/Users/ted/montty"
        )
        let picked = PaneTint(stops: [.named(.cyan), .hex(RGB(r: 9, g: 9, b: 9))])
        let tint = TabColor.paneTint(
            for: info, overrides: ["/Users/ted/montty": picked]
        )
        #expect(tint == picked)
    }

    @Test func noOverrideAndNoRepoIsNil() {
        let tint = TabColor.resolvedPaneTint(
            surfaceOverride: nil,
            tabColorOverride: nil,
            surfaceDirectory: "/tmp",
            repoColorOverrides: [:]
        )
        #expect(tint == nil)
    }

    @Test func tabExposesPerSurfaceOverride() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        tab.surfaceColorOverrides[surfaceID] = surfaceTint
        #expect(tab.effectivePaneTint() == surfaceTint)
    }

    @Test func surfaceOverrideOnFocusedPaneShowsInSidebar() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        tab.colorOverride = tabTint
        tab.surfaceColorOverrides[surfaceID] = surfaceTint
        #expect(tab.effectiveColor() == surfaceTint.primary)
    }
}
