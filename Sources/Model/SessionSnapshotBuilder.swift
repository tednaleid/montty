// ABOUTME: Builds a SessionSnapshot from the windows currently open. Pure --
// ABOUTME: takes the app-layer values it needs as arguments, so it is testable
// ABOUTME: without AppKit or a live SessionStore.

import Foundation

/// The two lookups only the app layer can answer: a window's real on-screen
/// frame, and a surface's live working directory. Bundled together so
/// `SessionSnapshotBuilder.snapshot` stays under SwiftLint's parameter limit.
struct SessionEnvironment {
    let frame: (WindowModel) -> WindowFrame
    let directory: (UUID) -> String?
}

enum SessionSnapshotBuilder {
    /// One snapshot per open window, in the shape `SessionStore` writes to
    /// disk.
    static func snapshot(
        windows: [WindowModel],
        keyWindowID: UUID?,
        surfaceTintEnabled: Bool,
        repoColorOverrides: [String: PaneTint],
        environment: SessionEnvironment
    ) -> SessionSnapshot {
        SessionSnapshot(
            surfaceTintEnabled: surfaceTintEnabled,
            windows: windows.map { window in
                WindowSnapshot(
                    windowID: window.id,
                    frame: environment.frame(window),
                    sidebarWidth: window.sidebarWidth,
                    activeTabID: window.tabStore.activeTabID,
                    tabs: window.tabStore.tabs.map { tabSnapshot(of: $0, environment: environment) }
                )
            },
            keyWindowID: keyWindowID,
            repoColorOverrides: repoColorOverrides
        )
    }

    /// One tab's persisted shape, including each leaf's working directory and
    /// color override keyed by leaf rather than by the surface id, which is
    /// minted fresh on restore.
    private static func tabSnapshot(of tab: Tab, environment: SessionEnvironment) -> TabSnapshot {
        var dirs: [UUID: String] = [:]
        var colors: [UUID: PaneTint] = [:]
        for leaf in SplitTree.allLeaves(node: tab.splitRoot) {
            if let pwd = environment.directory(leaf.surfaceID) {
                dirs[leaf.id] = pwd
            }
            if let tint = tab.surfaceColorOverrides[leaf.surfaceID] {
                colors[leaf.id] = tint
            }
        }
        return TabSnapshot(
            tabID: tab.id,
            name: tab.name,
            position: tab.position,
            focusedLeafID: tab.focusedLeafID,
            splitLayout: tab.splitRoot,
            leafDirectories: dirs,
            leafColorOverrides: colors,
            colorOverride: tab.colorOverride
        )
    }
}
