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

    /// Surface jump mode state (nil = normal mode).
    @Published var jumpState: JumpState?

    /// Sidebar width, persisted across sessions.
    @Published var sidebarWidth: Double = 200

    /// Whether the sidebar is visible.
    @Published var sidebarVisible = true

    /// Whether surface background tinting is enabled.
    @Published var surfaceTintEnabled = true
    /// Per-repo/worktree color overrides, keyed by repo identity string.
    @Published var repoColorOverrides: [String: TabColor] = [:]
    /// ANSI palette colors from the Ghostty config (14 colors, reordered).
    /// Indexed by TabColor.orderedCases position. Empty before config loads.
    var tabPalette: [NSColor] = []

    /// Resolve the AppDelegate through SwiftUI's @NSApplicationDelegateAdaptor wrapper.
    static func shared() -> AppDelegate? {
        guard let delegate = NSApp?.delegate else { return nil }
        if let appDel = delegate as? AppDelegate { return appDel }
        for child in Mirror(reflecting: delegate).children {
            if let appDel = child.value as? AppDelegate { return appDel }
        }
        return nil
    }

    /// UndoManager accessed by Ghostty.App.swift for undo/redo routing
    let undoManager: UndoManager? = nil

    /// Surface views keyed by surface UUID. SwiftUI can't hold NSView
    /// references in the model layer, so AppDelegate owns them.
    private var surfaces: [UUID: Ghostty.SurfaceView] = [:]

    /// Combine subscriptions for surface property observation
    private var surfaceObservers: [UUID: Set<AnyCancellable>] = [:]

    /// Tick timer for the Ghostty event loop
    private var tickTimer: Timer?

    /// NSEvent monitor for capturing keys during jump mode
    private var jumpKeyMonitor: Any?

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

        // Load ANSI palette from Ghostty config for tab colors
        loadTabPalette()
        NotificationCenter.default.addObserver(
            forName: .ghosttyConfigDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.loadTabPalette()
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

        // Build the main menu bar
        MenuBuilder.buildMainMenu(config: ghostty.config, appDelegate: self)

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
        // Inherit the focused surface's working directory
        if let focusedSurfaceID = tab.focusedSurfaceID,
           let pwd = surfaces[focusedSurfaceID]?.pwd {
            config.workingDirectory = pwd
        }
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

    /// Update focus state for all surfaces in a tab so only the focused
    /// pane has an active cursor and accepts key equivalents.
    func updateSurfaceFocus(for tab: Tab) {
        let focusedSurfaceID = tab.focusedSurfaceID
        for leaf in SplitTree.allLeaves(node: tab.splitRoot) {
            guard let view = surfaces[leaf.surfaceID] else { continue }
            let shouldFocus = leaf.surfaceID == focusedSurfaceID
            // Use focusDidChange to update both the Swift-side focused
            // flag and the C-side ghostty_surface_set_focus.
            view.focusDidChange(shouldFocus)
        }
    }

    func surfaceView(for surfaceID: UUID) -> Ghostty.SurfaceView? {
        surfaces[surfaceID]
    }

    // MARK: - Surface jump mode

    func enterJumpMode() {
        // Collect all surfaces: active tab first, then other tabs by position
        var targets: [JumpTarget] = []
        let activeID = tabStore.activeTabID

        // Active tab surfaces first (skip the currently focused surface)
        if let activeTab = tabStore.activeTab {
            for leaf in SplitTree.allLeaves(node: activeTab.splitRoot)
                where leaf.id != activeTab.focusedLeafID {
                targets.append(JumpTarget(tabID: activeTab.id, leafID: leaf.id))
            }
        }

        // Other tabs by position
        for tab in tabStore.tabs where tab.id != activeID {
            for leaf in SplitTree.allLeaves(node: tab.splitRoot) {
                targets.append(JumpTarget(tabID: tab.id, leafID: leaf.id))
            }
        }

        guard !targets.isEmpty else { return }

        jumpState = JumpLabels.assign(targets: targets)
        installJumpKeyMonitor()
    }

    func exitJumpMode() {
        jumpState = nil
        removeJumpKeyMonitor()
    }

    /// Jump to a specific surface (used by both jump mode and minimap click).
    func jumpToSurface(tabID: UUID, leafID: UUID) {
        guard let tab = tabStore.tabs.first(where: { $0.id == tabID }) else { return }
        if tabStore.activeTabID != tabID {
            tabStore.activeTabID = tabID
        }
        setFocusedLeaf(leafID, in: tab)
    }

    private func installJumpKeyMonitor() {
        removeJumpKeyMonitor()
        jumpKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.jumpState != nil else { return event }

            // Escape cancels
            if event.keyCode == 53 {
                self.exitJumpMode()
                return nil
            }

            // Only handle unmodified letter keys
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    .subtracting([.capsLock, .numericPad, .function]).isEmpty,
                  let chars = event.charactersIgnoringModifiers,
                  let key = chars.first,
                  key.isLetter else {
                self.exitJumpMode()
                return nil
            }

            guard let state = self.jumpState else { return event }
            let (newState, target) = JumpLabels.handleKey(
                Character(key.lowercased()), state: state
            )

            if let target {
                self.exitJumpMode()
                self.jumpToSurface(tabID: target.tabID, leafID: target.leafID)
            } else {
                self.jumpState = newState // nil cancels, non-nil buffers prefix
                if newState == nil {
                    self.removeJumpKeyMonitor()
                }
            }

            return nil // consume the event
        }
    }

    private func removeJumpKeyMonitor() {
        if let monitor = jumpKeyMonitor {
            NSEvent.removeMonitor(monitor)
            jumpKeyMonitor = nil
        }
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
            .sink { [weak tab, id = surfaceView.id] pwd in
                tab?.surfaceDirectories[id] = pwd
            }
            .store(in: &cancellables)

        surfaceObservers[surfaceView.id] = cancellables
    }

    // MARK: - Menu actions

    /// Handle a menu item that triggers a Ghostty binding action.
    @objc func handleMenuAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? String,
              let tab = tabStore.activeTab,
              let surfaceID = tab.focusedSurfaceID,
              let view = surfaceView(for: surfaceID),
              let surface = view.surface else { return }
        ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
    }

    /// Open the Ghostty config file in the default editor.
    func openConfig() {
        let configPath = NSHomeDirectory() + "/.config/ghostty/config"
        NSWorkspace.shared.open(URL(fileURLWithPath: configPath))
    }

    // MARK: - Ghostty action routing

    // MARK: - Tab palette

    /// Read the ANSI-16 palette from Ghostty config and build a 14-color
    /// tab palette by dropping black/white variants based on theme brightness.
    func loadTabPalette() {
        guard let cfg = ghostty.config.config else { return }

        // Read the full 256-color palette via the C API
        var palette = ghostty_config_palette_s()
        let key = "palette"
        if ghostty_config_get(cfg, &palette, key, UInt(key.utf8.count)) {
            // Extract the first 16 ANSI colors from the C tuple
            let all16: [NSColor] = withUnsafeBytes(of: palette.colors) { buf in
                let bound = buf.bindMemory(to: ghostty_config_color_s.self)
                return Array(bound.prefix(16)).map { NSColor(ghostty: $0) }
            }

            // Determine if the theme is dark or light from the background color
            var background = ghostty_config_color_s()
            let bgKey = "background"
            let isDark: Bool
            if ghostty_config_get(cfg, &background, bgKey, UInt(bgKey.utf8.count)) {
                let lum = 0.299 * Double(background.r) + 0.587 * Double(background.g)
                    + 0.114 * Double(background.b)
                isDark = lum < 128
            } else {
                isDark = true
            }

            // ANSI indices reordered for maximum hue diversity.
            // Dark: drop 0 (black) and 8 (bright black), use 7 and 15.
            // Light: drop 7 (white) and 15 (bright white), use 0 and 8.
            let indices = isDark
                ? [4, 1, 2, 3, 5, 6, 7, 12, 9, 10, 11, 13, 14, 15]
                : [4, 1, 2, 3, 5, 6, 0, 12, 9, 10, 11, 13, 14, 8]

            tabPalette = indices.map { all16[$0] }
        }
    }

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
                position: tab.position,
                focusedLeafID: tab.focusedLeafID,
                splitLayout: tab.splitRoot,
                leafDirectories: dirs,
                colorOverride: tab.colorOverride
            )
        }
        return SessionSnapshot(
            windowX: frame.origin.x,
            windowY: frame.origin.y,
            windowWidth: frame.width,
            windowHeight: frame.height,
            sidebarWidth: sidebarWidth,
            surfaceTintEnabled: surfaceTintEnabled,
            activeTabID: tabStore.activeTabID,
            tabs: tabSnapshots,
            repoColorOverrides: repoColorOverrides
        )
    }

    private func restoreSession(_ snapshot: SessionSnapshot) {
        guard let app = ghostty.app, !snapshot.tabs.isEmpty else {
            createTab()
            return
        }

        sidebarWidth = snapshot.sidebarWidth
        surfaceTintEnabled = snapshot.surfaceTintEnabled
        repoColorOverrides = snapshot.repoColorOverrides

        for tabSnap in snapshot.tabs.sorted(by: { $0.position < $1.position }) {
            let tab = Tab(
                id: tabSnap.tabID,
                name: tabSnap.name,
                position: tabSnap.position
            )
            // Rebuild the split tree with fresh surfaces
            tab.splitRoot = restoreSplitNode(
                tabSnap.splitLayout,
                directories: tabSnap.leafDirectories,
                app: app, tab: tab
            )
            tab.focusedLeafID = tabSnap.focusedLeafID
            tab.colorOverride = tabSnap.colorOverride
            tabStore.append(tab: tab)
        }

        tabStore.activeTabID = snapshot.activeTabID ?? tabStore.tabs.first?.id

        // Restore window frame and sync focus after SwiftUI has laid out
        // the view hierarchy. Must happen after layout because:
        // 1. Window frame needs the views to exist
        // 2. Each surface calls becomeFirstResponder when added to the
        //    window, resetting focus -- we need the last word.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            if snapshot.windowWidth > 0, snapshot.windowHeight > 0 {
                let frame = CGRect(
                    x: snapshot.windowX, y: snapshot.windowY,
                    width: snapshot.windowWidth, height: snapshot.windowHeight
                )
                NSApp.mainWindow?.setFrame(frame, display: true)
            }
            for tab in self.tabStore.tabs {
                self.updateSurfaceFocus(for: tab)
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
            // Set surface directory for immediate UI display (surface will
            // update it via observer once the shell reports its pwd)
            if let dir = directories[leaf.id] {
                tab.surfaceDirectories[surfaceView.id] = dir
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
