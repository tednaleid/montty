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
}
