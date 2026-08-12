// ABOUTME: Builds and restores SessionSnapshot state -- tab layout, per-surface
// ABOUTME: working directories, and color overrides survive a relaunch.

import AppKit
import Foundation
import GhosttyKit

extension AppDelegate {
    /// A thin call into the pure builder, supplying the two values only this
    /// layer can: a window's real on-screen frame, and a surface's working
    /// directory.
    func createSnapshot() -> SessionSnapshot {
        SessionSnapshotBuilder.snapshot(
            windows: registry.windows,
            keyWindowID: registry.keyWindowID,
            surfaceTintEnabled: surfaceTintEnabled,
            repoColorOverrides: repoColorOverrides,
            environment: SessionEnvironment(
                frame: { [weak self] window in
                    WindowFrame(self?.controllers[window.id]?.window.frame ?? .zero)
                },
                directory: { [weak self] surfaceID in
                    self?.surfaceView(for: surfaceID)?.pwd
                }
            )
        )
    }

    func restoreSession(_ snapshot: SessionSnapshot) {
        let restorable = snapshot.windows.filter { !$0.tabs.isEmpty }
        guard let app = ghostty.app, !restorable.isEmpty else {
            // A quit that closed every window saves no windows, so this is a
            // normal cold launch and needs focus like any other.
            let controller = makeWindow()
            controller.show()
            createTab(in: controller.model)
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
