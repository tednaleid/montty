// ABOUTME: Verifies SessionSnapshotBuilder.snapshot -- the shipped function
// ABOUTME: AppDelegate.createSnapshot() calls -- records exactly the windows
// ABOUTME: that are open, so a window closed by hand does not come back.

import Foundation
import Testing

@Suite struct SessionRestoreShapeTests {
    /// A window with one tab holding a single leaf, so tests can assert on
    /// that leaf's directory and color override as well as the window itself.
    private func windowWithTab(
        sidebarWidth: Double = 200,
        surfaceID: UUID = UUID(),
        tint: PaneTint? = nil
    ) -> WindowModel {
        let window = WindowModel(sidebarWidth: sidebarWidth)
        let tab = Tab(id: UUID(), name: "", position: 0)
        let leafID = UUID()
        tab.splitRoot = .leaf(SurfaceLeaf(id: leafID, surfaceID: surfaceID))
        tab.focusedLeafID = leafID
        if let tint {
            tab.surfaceColorOverrides[surfaceID] = tint
        }
        window.tabStore.append(tab: tab)
        return window
    }

    private func snapshot(
        of registry: WindowRegistry,
        directory: @escaping (UUID) -> String? = { _ in nil }
    ) -> SessionSnapshot {
        SessionSnapshotBuilder.snapshot(
            windows: registry.windows,
            keyWindowID: registry.keyWindowID,
            surfaceTintEnabled: true,
            repoColorOverrides: [:],
            environment: SessionEnvironment(
                frame: { _ in WindowFrame(x: 0, y: 0, width: 0, height: 0) },
                directory: directory
            )
        )
    }

    @Test func recordsEveryOpenWindow() {
        let registry = WindowRegistry()
        registry.add(windowWithTab())
        registry.add(windowWithTab())

        #expect(snapshot(of: registry).windows.count == 2)
    }

    @Test func forgetsAWindowThatWasClosed() {
        let registry = WindowRegistry()
        let first = registry.add(windowWithTab())
        registry.add(windowWithTab())

        registry.remove(id: first.id)

        let recorded = snapshot(of: registry)
        #expect(recorded.windows.count == 1)
        #expect(!recorded.windows.contains { $0.windowID == first.id })
    }

    @Test func recordsNoWindowsWhenEveryWindowIsClosed() {
        let registry = WindowRegistry()
        let only = registry.add(windowWithTab())

        registry.remove(id: only.id)

        #expect(snapshot(of: registry).windows.isEmpty)
    }

    @Test func capturesEachWindowsFrameSidebarAndKeyID() {
        let registry = WindowRegistry()
        let window = registry.add(windowWithTab(sidebarWidth: 260))
        registry.keyWindowID = window.id

        let recorded = SessionSnapshotBuilder.snapshot(
            windows: registry.windows,
            keyWindowID: registry.keyWindowID,
            surfaceTintEnabled: false,
            repoColorOverrides: [:],
            environment: SessionEnvironment(
                frame: { _ in WindowFrame(x: 10, y: 20, width: 300, height: 400) },
                directory: { _ in nil }
            )
        )

        #expect(recorded.keyWindowID == window.id)
        #expect(recorded.surfaceTintEnabled == false)
        let saved = recorded.windows.first
        #expect(saved?.windowID == window.id)
        #expect(saved?.sidebarWidth == 260)
        #expect(saved?.frame == WindowFrame(x: 10, y: 20, width: 300, height: 400))
        #expect(saved?.tabs.count == 1)
    }

    @Test func capturesEachLeafsDirectory() {
        let registry = WindowRegistry()
        let surfaceID = UUID()
        registry.add(windowWithTab(surfaceID: surfaceID))

        let recorded = snapshot(of: registry) { id in id == surfaceID ? "/tmp/work" : nil }

        #expect(recorded.windows.first?.tabs.first?.leafDirectories.values.first == "/tmp/work")
    }

    @Test func capturesEachLeafsColorOverride() {
        let registry = WindowRegistry()
        let surfaceID = UUID()
        let tint = PaneTint(stops: [.named(.blue)])
        registry.add(windowWithTab(surfaceID: surfaceID, tint: tint))

        let recorded = snapshot(of: registry)

        #expect(recorded.windows.first?.tabs.first?.leafColorOverrides.values.first == tint)
    }
}
