// ABOUTME: Regression coverage for the state round-trip the menu and CLI
// ABOUTME: adapters perform through ControlService against a Tab's fields.

import Foundation
import Testing

@Suite struct ControlAdapterTests {
    @Test func menuStyleClearRemovesACLISetGradient() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        let ref = SurfaceRef(
            monttyID: "M1", surfaceID: surfaceID, leafID: UUID(),
            tabID: tab.id, directory: nil
        )

        var state = ControlState(
            tabName: tab.name, autoName: tab.autoName,
            surfaceColorOverrides: tab.surfaceColorOverrides,
            tabColorOverride: tab.colorOverride,
            repoColorOverrides: [:], activityStates: [:], activityWaitingSince: [:]
        )

        let gradient = PaneTint(stops: [.named(.neutralBright), .hex(RGB(r: 0x1A, g: 0x7F, b: 0x37))])
        _ = ControlService.apply(
            .setColor(scope: .surface, tint: gradient), target: ref, to: &state
        )
        #expect(state.surfaceColorOverrides[surfaceID] == gradient)

        _ = ControlService.apply(.clearColor(scope: .surface), target: ref, to: &state)
        #expect(state.surfaceColorOverrides[surfaceID] == nil)
    }

    @Test func stateWritesBackOntoTheTab() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        var state = ControlState(
            tabName: "", autoName: "", surfaceColorOverrides: [:],
            tabColorOverride: nil, repoColorOverrides: [:],
            activityStates: [:], activityWaitingSince: [:]
        )
        let ref = SurfaceRef(
            monttyID: "M1", surfaceID: surfaceID, leafID: UUID(),
            tabID: tab.id, directory: nil
        )

        _ = ControlService.apply(.setName("MR !123"), target: ref, to: &state)
        tab.name = state.tabName
        tab.surfaceColorOverrides = state.surfaceColorOverrides
        tab.colorOverride = state.tabColorOverride

        #expect(tab.displayName == "MR !123")
    }
}
