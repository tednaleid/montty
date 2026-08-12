// ABOUTME: Builds and restores SessionSnapshot state -- tab layout, per-surface
// ABOUTME: working directories, and color overrides survive a relaunch.

import AppKit
import Foundation
import GhosttyKit

extension AppDelegate {
    func createSnapshot() -> SessionSnapshot {
        SessionSnapshot(
            surfaceTintEnabled: surfaceTintEnabled,
            windows: registry.windows.map { window in
                WindowSnapshot(
                    windowID: window.id,
                    frame: WindowFrame(controllers[window.id]?.window.frame ?? .zero),
                    sidebarWidth: window.sidebarWidth,
                    activeTabID: window.tabStore.activeTabID,
                    tabs: window.tabStore.tabs.map(tabSnapshot(of:))
                )
            },
            keyWindowID: registry.keyWindowID,
            repoColorOverrides: repoColorOverrides
        )
    }

    /// One tab's persisted shape, including each leaf's working directory and
    /// color override keyed by leaf rather than by the surface id, which is
    /// minted fresh on restore.
    private func tabSnapshot(of tab: Tab) -> TabSnapshot {
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

    func restoreSession(_ snapshot: SessionSnapshot) {
        let restorable = snapshot.windows.filter { !$0.tabs.isEmpty }
        guard let app = ghostty.app, !restorable.isEmpty else {
            // A quit that closed every window saves no windows, so this is a
            // normal cold launch and needs focus like any other.
            let controller = makeWindow()
            controller.show()
            createTab()
            focusActiveSurface()
            return
        }

        surfaceTintEnabled = snapshot.surfaceTintEnabled
        repoColorOverrides = snapshot.repoColorOverrides

        for windowSnap in restorable {
            let model = WindowModel(
                id: windowSnap.windowID,
                sidebarWidth: windowSnap.sidebarWidth,
                frame: windowSnap.frame
            )
            let controller = makeWindow(model)
            for tabSnap in windowSnap.tabs.sorted(by: { $0.position < $1.position }) {
                let tab = Tab(
                    id: tabSnap.tabID, name: tabSnap.name, position: tabSnap.position
                )
                tab.splitRoot = restoreSplitNode(
                    tabSnap.splitLayout,
                    directories: tabSnap.leafDirectories,
                    colors: tabSnap.leafColorOverrides,
                    app: app, tab: tab
                )
                tab.focusedLeafID = tabSnap.focusedLeafID
                tab.colorOverride = tabSnap.colorOverride
                model.tabStore.append(tab: tab)
            }
            model.tabStore.activeTabID =
                windowSnap.activeTabID ?? model.tabStore.tabs.first?.id
            controller.show()
        }

        registry.keyWindowID = snapshot.keyWindowID ?? registry.windows.first?.id
        keyController?.window.makeKeyAndOrderFront(nil)

        // Frames and focus settle after SwiftUI lays the hierarchy out. Each
        // surface calls becomeFirstResponder when it joins a window, so focus
        // needs the last word.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            let visible = NSScreen.screens.map(\.visibleFrame)
            for window in self.registry.windows where !window.frame.isEmpty {
                self.controllers[window.id]?.window.setFrame(
                    window.frame.clamped(toVisible: visible).rect, display: true
                )
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
