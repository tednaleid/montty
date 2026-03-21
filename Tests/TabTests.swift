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
        #expect(tab.surfaceID == surfaceID)
    }
}
