import Cocoa
import Combine
import GhosttyKit
import os
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, GhosttyAppDelegate, ObservableObject {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.montty.app",
        category: "app"
    )

    @Published var ghostty: Ghostty.App
    let tabStore = TabStore()

    /// UndoManager accessed by Ghostty.App.swift for undo/redo routing
    let undoManager: UndoManager? = nil

    /// Surface views keyed by surface UUID. SwiftUI can't hold NSView
    /// references in the model layer, so AppDelegate owns them.
    private var surfaces: [UUID: Ghostty.SurfaceView] = [:]

    /// Combine subscriptions for surface property observation
    private var surfaceObservers: [UUID: Set<AnyCancellable>] = [:]

    /// Tick timer for the Ghostty event loop
    private var tickTimer: Timer?

    /// Session persistence
    private let sessionStore = SessionStore()

    override init() {
        // Point GhosttyKit at our bundled resources (terminfo + shell
        // integration scripts copied from the Ghostty submodule at build time).
        if let resourcePath = Bundle.main.resourcePath {
            setenv("GHOSTTY_RESOURCES_DIR", resourcePath + "/ghostty", 1)
        }

        // ghostty_init must be called before any other GhosttyKit API
        if ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != GHOSTTY_SUCCESS {
            AppDelegate.logger.critical("ghostty_init failed")
        }
        self.ghostty = Ghostty.App()
        super.init()
        self.ghostty.delegate = self
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start the Ghostty event loop tick timer
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.ghostty.appTick()
        }

        // Restore previous session or create a fresh tab
        if let snapshot = sessionStore.load() {
            restoreSession(snapshot)
        } else {
            createTab()
        }

        // Observe Ghostty action notifications for tab operations
        observeGhosttyActions()

        // Auto-save session every 8 seconds
        sessionStore.startAutoSave { [weak self] in
            self?.createSnapshot() ?? SessionSnapshot()
        }

        HookServer.start()
        #if DEBUG
        DebugServer.start()
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionStore.stopAutoSave()
        sessionStore.save(snapshot: createSnapshot())

        HookServer.stop()
        #if DEBUG
        DebugServer.stop()
        #endif

        tickTimer?.invalidate()
        tickTimer = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - Tab lifecycle

    /// Port for the debug HTTP server (debug builds only).
    static let hookPort = 9876

    func createTab() {
        guard let app = ghostty.app else { return }
        let monttyID = UUID().uuidString
        var config = Ghostty.SurfaceConfiguration()
        config.environmentVariables["MONTTY_SURFACE_ID"] = monttyID
        config.environmentVariables["MONTTY_PORT"] = String(Self.hookPort)
        config.environmentVariables["MONTTY_SOCKET"] = HookServer.socketPath
        let surfaceView = Ghostty.SurfaceView(app, baseConfig: config)
        let tab = Tab(surfaceID: surfaceView.id)
        tab.surfaceToMonttyID[surfaceView.id] = monttyID
        surfaces[surfaceView.id] = surfaceView
        tabStore.append(tab: tab)
        tabStore.activeTabID = tab.id

        // Watch for title and PWD changes from this surface
        observeSurface(surfaceView, tab: tab)
    }

    func closeTab(id: UUID) {
        guard let tab = tabStore.tabs.first(where: { $0.id == id }) else { return }
        // Clean up all surfaces in this tab's split tree
        for surfaceID in tab.allSurfaceIDs {
            surfaceObservers.removeValue(forKey: surfaceID)
            surfaces.removeValue(forKey: surfaceID)
        }
        tabStore.close(id: id)

        // If no tabs remain, quit
        if tabStore.tabs.isEmpty {
            NSApplication.shared.terminate(nil)
        }
    }

    /// Close a single surface within a tab's split tree.
    /// If it's the last surface, closes the tab.
    func closeSurface(surfaceID: UUID) {
        guard let tab = tabStore.tab(forSurfaceID: surfaceID) else { return }
        guard let leaf = SplitTree.findLeaf(
            node: tab.splitRoot, surfaceID: surfaceID
        ) else { return }

        surfaceObservers.removeValue(forKey: surfaceID)
        surfaces.removeValue(forKey: surfaceID)

        // Pre-compute focus target before modifying the tree
        let focusTarget = SplitTree.nextLeaf(node: tab.splitRoot, after: leaf.id)
            ?? SplitTree.previousLeaf(node: tab.splitRoot, before: leaf.id)

        if let newRoot = SplitTree.close(node: tab.splitRoot, leafID: leaf.id) {
            tab.splitRoot = newRoot
            let leaves = SplitTree.allLeaves(node: newRoot)
            if let targetID = focusTarget?.id ?? leaves.first?.id {
                setFocusedLeaf(targetID, in: tab)
            }
        } else {
            // Last surface in tab -- close the tab
            closeTab(id: tab.id)
        }
    }

    /// Split the focused surface in the active tab.
    func splitSurface(direction: SplitDirection) {
        guard let app = ghostty.app,
              let tab = tabStore.activeTab,
              let focusedLeafID = tab.focusedLeafID else { return }

        let monttyID = UUID().uuidString
        var config = Ghostty.SurfaceConfiguration()
        config.environmentVariables["MONTTY_SURFACE_ID"] = monttyID
        config.environmentVariables["MONTTY_PORT"] = String(Self.hookPort)
        config.environmentVariables["MONTTY_SOCKET"] = HookServer.socketPath
        let newSurfaceView = Ghostty.SurfaceView(app, baseConfig: config)
        let newLeafID = UUID()
        surfaces[newSurfaceView.id] = newSurfaceView
        tab.surfaceToMonttyID[newSurfaceView.id] = monttyID

        tab.splitRoot = SplitTree.split(
            node: tab.splitRoot,
            leafID: focusedLeafID,
            direction: direction,
            newLeafID: newLeafID,
            newSurfaceID: newSurfaceView.id
        )
        observeSurface(newSurfaceView, tab: tab)
        setFocusedLeaf(newLeafID, in: tab)
    }

    /// Set the focused leaf for a tab and sync Ghostty's focus state.
    func setFocusedLeaf(_ leafID: UUID, in tab: Tab) {
        tab.focusedLeafID = leafID
        updateSurfaceFocus(for: tab)
        if let surfaceID = tab.focusedSurfaceID,
           let surfaceView = surfaces[surfaceID] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Ghostty.moveFocus(to: surfaceView)
            }
        }
    }

    /// Update ghostty_surface_set_focus for all surfaces in the active tab
    /// so only the focused pane has an active cursor.
    func updateSurfaceFocus(for tab: Tab) {
        let focusedSurfaceID = tab.focusedSurfaceID
        for leaf in SplitTree.allLeaves(node: tab.splitRoot) {
            guard let view = surfaces[leaf.surfaceID],
                  let surface = view.surface else { continue }
            ghostty_surface_set_focus(surface, leaf.surfaceID == focusedSurfaceID)
        }
    }

    func surfaceView(for surfaceID: UUID) -> Ghostty.SurfaceView? {
        surfaces[surfaceID]
    }

    // MARK: - Surface observation

    private func observeSurface(_ surfaceView: Ghostty.SurfaceView, tab: Tab) {
        var cancellables = Set<AnyCancellable>()

        surfaceView.$title
            .receive(on: DispatchQueue.main)
            .sink { [weak tab, id = surfaceView.id] title in
                tab?.autoName = title
                tab?.surfaceTitles[id] = title
            }
            .store(in: &cancellables)

        surfaceView.$pwd
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak tab] pwd in
                tab?.workingDirectory = pwd
            }
            .store(in: &cancellables)

        surfaceObservers[surfaceView.id] = cancellables
    }

    // MARK: - Ghostty action routing

    // MARK: - Session persistence

    func createSnapshot() -> SessionSnapshot {
        let frame = NSApp.mainWindow?.frame ?? .zero
        let tabSnapshots = tabStore.tabs.map { tab -> TabSnapshot in
            var dirs: [UUID: String] = [:]
            for leaf in SplitTree.allLeaves(node: tab.splitRoot) {
                if let pwd = surfaces[leaf.surfaceID]?.pwd {
                    dirs[leaf.id] = pwd
                }
            }
            return TabSnapshot(
                tabID: tab.id,
                name: tab.name,
                color: tab.color,
                position: tab.position,
                focusedLeafID: tab.focusedLeafID,
                splitLayout: tab.splitRoot,
                leafDirectories: dirs
            )
        }
        return SessionSnapshot(
            windowX: frame.origin.x,
            windowY: frame.origin.y,
            windowWidth: frame.width,
            windowHeight: frame.height,
            activeTabID: tabStore.activeTabID,
            tabs: tabSnapshots
        )
    }

    private func restoreSession(_ snapshot: SessionSnapshot) {
        guard let app = ghostty.app, !snapshot.tabs.isEmpty else {
            createTab()
            return
        }

        for tabSnap in snapshot.tabs.sorted(by: { $0.position < $1.position }) {
            let tab = Tab(
                id: tabSnap.tabID,
                name: tabSnap.name,
                color: tabSnap.color,
                position: tabSnap.position
            )
            // Rebuild the split tree with fresh surfaces
            tab.splitRoot = restoreSplitNode(
                tabSnap.splitLayout,
                directories: tabSnap.leafDirectories,
                app: app, tab: tab
            )
            tab.focusedLeafID = tabSnap.focusedLeafID
            tabStore.append(tab: tab)
        }

        tabStore.activeTabID = snapshot.activeTabID ?? tabStore.tabs.first?.id

        // Sync Ghostty focus state so only the focused pane has an active cursor
        if let activeTab = tabStore.activeTab {
            updateSurfaceFocus(for: activeTab)
        }

        // Restore window frame after a brief delay to let SwiftUI lay out
        if snapshot.windowWidth > 0, snapshot.windowHeight > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let frame = CGRect(
                    x: snapshot.windowX, y: snapshot.windowY,
                    width: snapshot.windowWidth, height: snapshot.windowHeight
                )
                NSApp.mainWindow?.setFrame(frame, display: true)
            }
        }
    }

    /// Recursively rebuild a SplitNode tree, creating fresh Ghostty surfaces
    /// for each leaf with the saved working directory.
    private func restoreSplitNode(
        _ node: SplitNode,
        directories: [UUID: String],
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
            let surfaceView = Ghostty.SurfaceView(app, baseConfig: config)
            tab.surfaceToMonttyID[surfaceView.id] = monttyID
            surfaces[surfaceView.id] = surfaceView
            observeSurface(surfaceView, tab: tab)
            // Set tab directory for immediate UI display (surface will
            // update it via observer once the shell reports its pwd)
            if let dir = directories[leaf.id] {
                tab.workingDirectory = dir
            }
            return .leaf(SurfaceLeaf(id: leaf.id, surfaceID: surfaceView.id))
        case .split(let branch):
            return .split(SplitBranch(
                id: branch.id,
                orientation: branch.orientation,
                ratio: branch.ratio,
                first: restoreSplitNode(
                    branch.first, directories: directories,
                    app: app, tab: tab),
                second: restoreSplitNode(
                    branch.second, directories: directories,
                    app: app, tab: tab)
            ))
        }
    }

    // MARK: - GhosttyAppDelegate

    func findSurface(forUUID uuid: UUID) -> Ghostty.SurfaceView? {
        surfaces[uuid]
    }

    // MARK: - Interface expected by Ghostty binding files

    func performGhosttyBindingMenuKeyEquivalent(with event: NSEvent) -> Bool {
        return false
    }

    func checkForUpdates(_ sender: Any?) {}
    func closeAllWindows(_ sender: Any?) {}
    func toggleVisibility(_ sender: Any?) {}
    func toggleQuickTerminal(_ sender: Any?) {}
    func setSecureInput(_ mode: Ghostty.SetSecureInput) {}
    func syncFloatOnTopMenu(_ window: NSWindow) {}
}
