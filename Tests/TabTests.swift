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

    @Test func defaultColorIsAuto() {
        let tab = Tab()
        #expect(tab.color == .auto)
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

    // MARK: - Effective color

    @Test func effectiveColorReturnsPresetWhenSet() {
        let tab = Tab(color: .preset(.red))
        #expect(tab.effectivePresetColor == .red)
    }

    @Test func effectiveColorDerivesFromGitRepoWhenAuto() {
        let surfaceID = UUID()
        let tab = Tab(color: .auto, surfaceID: surfaceID)
        // Use a path that's actually in a git repo (this project)
        let repoPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().path
        tab.surfaceDirectories[surfaceID] = repoPath
        let color = tab.effectivePresetColor
        // Should derive a color from the git repo, not gray
        #expect(color != .gray)
        // Should be deterministic
        #expect(color == tab.effectivePresetColor)
    }

    @Test func effectiveColorReturnsGrayForNonGitDirectory() {
        let surfaceID = UUID()
        let tab = Tab(color: .auto, surfaceID: surfaceID)
        tab.surfaceDirectories[surfaceID] = "/tmp"
        #expect(tab.effectivePresetColor == .gray)
    }

    @Test func effectiveColorReturnsGrayWhenNoDirectory() {
        let tab = Tab(color: .auto)
        #expect(tab.effectivePresetColor == .gray)
    }
}
