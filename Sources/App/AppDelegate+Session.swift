// ABOUTME: Builds and restores SessionSnapshot state -- tab layout, per-surface
// ABOUTME: working directories, and color overrides survive a relaunch.

import AppKit
import Foundation
import GhosttyKit

extension AppDelegate {
    func createSnapshot() -> SessionSnapshot {
        let frame = window?.frame ?? .zero
        let tabSnapshots = tabStore.tabs.map { tab -> TabSnapshot in
            var dirs: [UUID: String] = [:]
            var colors: [UUID: PaneTint] = [:]
            for leaf in SplitTree.allLeaves(node: tab.splitRoot) {
                if let pwd = surfaceView(for: leaf.surfaceID)?.pwd {
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
        return SessionSnapshot(
            surfaceTintEnabled: surfaceTintEnabled,
            windows: [WindowSnapshot(
                windowID: singleWindowID,
                frame: WindowFrame(frame),
                sidebarWidth: sidebarWidth,
                activeTabID: tabStore.activeTabID,
                tabs: tabSnapshots
            )],
            keyWindowID: singleWindowID,
            repoColorOverrides: repoColorOverrides
        )
    }

    func restoreSession(_ snapshot: SessionSnapshot) {
        guard let app = ghostty.app, let windowSnap = snapshot.windows.first,
              !windowSnap.tabs.isEmpty else {
            // A quit that closed every window saves no windows, so this is a
            // normal cold launch and needs focus like any other.
            createTab()
            focusActiveSurface()
            return
        }

        sidebarWidth = windowSnap.sidebarWidth
        surfaceTintEnabled = snapshot.surfaceTintEnabled
        repoColorOverrides = snapshot.repoColorOverrides

        for tabSnap in windowSnap.tabs.sorted(by: { $0.position < $1.position }) {
            let tab = Tab(
                id: tabSnap.tabID,
                name: tabSnap.name,
                position: tabSnap.position
            )
            // Rebuild the split tree with fresh surfaces
            tab.splitRoot = restoreSplitNode(
                tabSnap.splitLayout,
                directories: tabSnap.leafDirectories,
                colors: tabSnap.leafColorOverrides,
                app: app, tab: tab
            )
            tab.focusedLeafID = tabSnap.focusedLeafID
            tab.colorOverride = tabSnap.colorOverride
            tabStore.append(tab: tab)
        }

        tabStore.activeTabID = windowSnap.activeTabID ?? tabStore.tabs.first?.id

        // Restore window frame and sync focus after SwiftUI has laid out
        // the view hierarchy. Must happen after layout because:
        // 1. Window frame needs the views to exist
        // 2. Each surface calls becomeFirstResponder when added to the
        //    window, resetting focus -- we need the last word.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            let saved = windowSnap.frame
            if !saved.isEmpty {
                let visible = NSScreen.screens.map(\.visibleFrame)
                self.window?.setFrame(saved.clamped(toVisible: visible).rect, display: true)
            }
            self.syncSurfaceFocus()
            self.focusActiveSurface()
        }
    }

    /// Recursively rebuild a SplitNode tree, creating fresh Ghostty surfaces
    /// for each leaf with the saved working directory and keying the color
    /// override map back onto the fresh surface ID it mints for each leaf.
    private func restoreSplitNode(
        _ node: SplitNode,
        directories: [UUID: String],
        colors: [UUID: PaneTint],
        app: ghostty_app_t,
        tab: Tab
    ) -> SplitNode {
        switch node {
        case .leaf(let leaf):
            let monttyID = UUID().uuidString
            var config = Ghostty.SurfaceConfiguration()
            config.workingDirectory = directories[leaf.id]
            config.environmentVariables["MONTTY_SURFACE_ID"] = monttyID
            config.environmentVariables["MONTTY_PORT"] = String(Self.hookPort)
            config.environmentVariables["MONTTY_SOCKET"] = HookServer.socketPath
            config.environmentVariables["MONTTY_BIN"] = Self.binPath
            let surfaceView = Ghostty.SurfaceView(app, baseConfig: config)
            registerSurface(surfaceView, tab: tab, monttyID: monttyID)
            // Set surface directory for immediate UI display (surface will
            // update it via observer once the shell reports its pwd)
            if let dir = directories[leaf.id] {
                tab.surfaceDirectories[surfaceView.id] = dir
            }
            if let tint = colors[leaf.id] {
                tab.surfaceColorOverrides[surfaceView.id] = tint
            }
            return .leaf(SurfaceLeaf(id: leaf.id, surfaceID: surfaceView.id))
        case .split(let branch):
            return .split(SplitBranch(
                id: branch.id,
                orientation: branch.orientation,
                ratio: branch.ratio,
                first: restoreSplitNode(
                    branch.first, directories: directories,
                    colors: colors, app: app, tab: tab),
                second: restoreSplitNode(
                    branch.second, directories: directories,
                    colors: colors, app: app, tab: tab)
            ))
        }
    }
}
