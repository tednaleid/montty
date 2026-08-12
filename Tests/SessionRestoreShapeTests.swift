// ABOUTME: Verifies the snapshot records exactly the windows that are open, so
// ABOUTME: a window closed by hand does not come back on the next launch.

import Foundation
import Testing

@Suite struct SessionRestoreShapeTests {
    private func snapshot(of registry: WindowRegistry) -> SessionSnapshot {
        SessionSnapshot(
            surfaceTintEnabled: true,
            windows: registry.windows.map { window in
                WindowSnapshot(
                    windowID: window.id,
                    frame: window.frame,
                    sidebarWidth: window.sidebarWidth,
                    activeTabID: window.tabStore.activeTabID,
                    tabs: []
                )
            },
            keyWindowID: registry.keyWindowID,
            repoColorOverrides: [:]
        )
    }

    @Test func recordsEveryOpenWindow() {
        let registry = WindowRegistry()
        registry.add()
        registry.add()

        #expect(snapshot(of: registry).windows.count == 2)
    }

    @Test func forgetsAWindowThatWasClosed() {
        let registry = WindowRegistry()
        let first = registry.add()
        registry.add()

        registry.remove(id: first.id)

        let recorded = snapshot(of: registry)
        #expect(recorded.windows.count == 1)
        #expect(!recorded.windows.contains { $0.windowID == first.id })
    }

    @Test func recordsNoWindowsWhenEveryWindowIsClosed() {
        let registry = WindowRegistry()
        let only = registry.add()

        registry.remove(id: only.id)

        #expect(snapshot(of: registry).windows.isEmpty)
    }
}
