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

    @Test func effectiveColorDerivesFromDirectoryWhenAuto() {
        let surfaceID = UUID()
        let tab = Tab(color: .auto, surfaceID: surfaceID)
        tab.surfaceDirectories[surfaceID] = "/Users/ted/projects/montty"
        let color = tab.effectivePresetColor
        // Should be deterministic
        #expect(color == TabColor.colorForDirectory("/Users/ted/projects/montty"))
    }

    @Test func effectiveColorFallsToWorkingDirectory() {
        // When surfaceDirectories doesn't have the focused surface,
        // fall back to tab.workingDirectory
        let tab = Tab(color: .auto)
        tab.workingDirectory = "/tmp"
        let color = tab.effectivePresetColor
        #expect(color == TabColor.colorForDirectory("/tmp"))
    }

    @Test func effectiveColorReturnsGrayWhenNoDirectory() {
        let tab = Tab(color: .auto)
        #expect(tab.effectivePresetColor == .gray)
    }
}
