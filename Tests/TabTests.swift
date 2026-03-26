import Foundation
import Testing

struct TabTests {
    @Test func displayNamePrefersUserName() {
        let tab = Tab(name: "my project")
        tab.autoName = "some-directory"
        #expect(tab.displayName == "my project")
    }

    @Test func displayNameFallsBackToAutoName() {
        let tab = Tab(name: "")
        tab.autoName = "workspace"
        #expect(tab.displayName == "workspace")
    }

    @Test func displayNameEmptyWhenBothEmpty() {
        let tab = Tab(name: "", autoName: "")
        #expect(tab.displayName == "")
    }

    @Test func surfaceIDIsAssigned() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        #expect(tab.focusedSurfaceID == surfaceID)
    }

    @Test func splitRootStartsAsLeaf() {
        let tab = Tab()
        guard case .leaf = tab.splitRoot else {
            Issue.record("Expected leaf as initial splitRoot")
            return
        }
        #expect(tab.focusedLeafID != nil)
    }

    @Test func allSurfaceIDsReturnsOne() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        #expect(tab.allSurfaceIDs == [surfaceID])
    }

    // MARK: - Focused surface ID edge cases

    @Test func focusedSurfaceIDFallsBackWhenLeafIDMissing() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        // Set focusedLeafID to a UUID that doesn't exist in the tree
        tab.focusedLeafID = UUID()
        // Should fall back to the first leaf's surfaceID
        #expect(tab.focusedSurfaceID == surfaceID)
    }

    @Test func focusedSurfaceIDFallsBackWhenLeafIDNil() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        tab.focusedLeafID = nil
        #expect(tab.focusedSurfaceID == surfaceID)
    }

    // MARK: - Effective color

    @Test func effectiveColorDerivesFromGitRepoWhenAuto() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        // Use a path that's actually in a git repo (this project)
        let repoPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().path
        tab.surfaceDirectories[surfaceID] = repoPath
        let color = tab.effectiveColor()
        // Should derive a color from the git repo, not gray
        #expect(color != .gray)
        // Should be deterministic
        #expect(color == tab.effectiveColor())
    }

    @Test func effectiveColorUseFocusedSurfaceDirectory() {
        // Two surfaces: one in a git repo, one not. Color should follow focus.
        let surfaceA = UUID()
        let surfaceB = UUID()
        let leafA = SurfaceLeaf(surfaceID: surfaceA)
        let leafB = SurfaceLeaf(surfaceID: surfaceB)
        let tab = Tab()
        tab.splitRoot = .split(SplitBranch(
            orientation: .horizontal,
            first: .leaf(leafA),
            second: .leaf(leafB)
        ))
        let repoPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().path
        tab.surfaceDirectories[surfaceA] = repoPath
        tab.surfaceDirectories[surfaceB] = "/tmp"

        // Focus surface A (git repo) -- should get a real color
        tab.focusedLeafID = leafA.id
        let colorA = tab.effectiveColor()
        #expect(colorA != .gray)

        // Focus surface B (non-git) -- should get gray
        tab.focusedLeafID = leafB.id
        #expect(tab.effectiveColor() == .gray)
    }

    @Test func effectiveColorReturnsGrayForNonGitDirectory() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        tab.surfaceDirectories[surfaceID] = "/tmp"
        #expect(tab.effectiveColor() == .gray)
    }

    @Test func effectiveColorReturnsGrayWhenNoDirectory() {
        let tab = Tab()
        #expect(tab.effectiveColor() == .gray)
    }

    @Test func effectiveColorRespectsOverride() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        let repoPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().path
        tab.surfaceDirectories[surfaceID] = repoPath

        let defaultColor = tab.effectiveColor()
        #expect(defaultColor != .gray)

        // Override to a different color
        let overrideColor: TabColor = (defaultColor == .magenta) ? .blue : .magenta
        let identity = TabColor.repoIdentity(for: repoPath)!
        let overrides = [identity: overrideColor]
        #expect(tab.effectiveColor(overrides: overrides) == overrideColor)
    }

    @Test func tabColorOverrideBeatsRepoOverride() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        let repoPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().path
        tab.surfaceDirectories[surfaceID] = repoPath

        // Set tab-level override
        tab.colorOverride = .cyan

        // Tab override should beat both hashed color and repo override
        #expect(tab.effectiveColor() == .cyan)
        let identity = TabColor.repoIdentity(for: repoPath)!
        let repoOverrides = [identity: TabColor.magenta]
        #expect(tab.effectiveColor(overrides: repoOverrides) == .cyan)
    }

    @Test func tabColorOverrideNilFallsThrough() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        let repoPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().path
        tab.surfaceDirectories[surfaceID] = repoPath

        tab.colorOverride = nil
        // Should use the git-hashed color, not gray
        #expect(tab.effectiveColor() != .gray)
    }
}
