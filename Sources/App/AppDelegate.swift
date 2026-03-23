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

        #if DEBUG
        DebugServer.start()
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionStore.stopAutoSave()
        sessionStore.save(snapshot: createSnapshot())

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

    func createTab() {
        guard let app = ghostty.app else { return }
        let surfaceView = Ghostty.SurfaceView(app)
        let tab = Tab(surfaceID: surfaceView.id)
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

        if let newRoot = SplitTree.close(node: tab.splitRoot, leafID: leaf.id) {
            tab.splitRoot = newRoot
            // Focus the next available leaf
            let leaves = SplitTree.allLeaves(node: newRoot)
            tab.focusedLeafID = leaves.first?.id
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

        let newSurfaceView = Ghostty.SurfaceView(app)
        let newLeafID = UUID()
        surfaces[newSurfaceView.id] = newSurfaceView

        tab.splitRoot = SplitTree.split(
            node: tab.splitRoot,
            leafID: focusedLeafID,
            direction: direction,
            newLeafID: newLeafID,
            newSurfaceID: newSurfaceView.id
        )
        tab.focusedLeafID = newLeafID
        observeSurface(newSurfaceView, tab: tab)
        updateSurfaceFocus(for: tab)

        // Move AppKit focus to the new surface after a brief delay
        // to let SwiftUI render the new view hierarchy
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Ghostty.moveFocus(to: newSurfaceView)
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
            .receive(on: DispatchQueue.main)
            .sink { [weak tab] pwd in
                tab?.workingDirectory = pwd
            }
            .store(in: &cancellables)

        surfaceObservers[surfaceView.id] = cancellables
    }

    // MARK: - Ghostty action routing

    private func observeGhosttyActions() {
        let center = NotificationCenter.default
        observeTabActions(center)
        observeSplitActions(center)
    }

    private func observeTabActions(_ center: NotificationCenter) {
        center.addObserver(
            forName: Ghostty.Notification.ghosttyNewTab,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.createTab()
        }

        center.addObserver(
            forName: .ghosttyCloseTab,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let surfaceView = notification.object as? Ghostty.SurfaceView,
                  let tab = self.tabStore.tab(forSurfaceID: surfaceView.id) else { return }
            self.closeTab(id: tab.id)
        }

        center.addObserver(
            forName: Ghostty.Notification.ghosttyCloseSurface,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let surfaceView = notification.object as? Ghostty.SurfaceView else { return }
            self.closeSurface(surfaceID: surfaceView.id)
        }

        center.addObserver(
            forName: Ghostty.Notification.ghosttyGotoTab,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let tabIndex = notification.userInfo?[
                      Ghostty.Notification.GotoTabKey
                  ] as? ghostty_action_goto_tab_e else { return }
            self.handleGotoTab(tabIndex)
        }
    }

    private func handleGotoTab(_ tabIndex: ghostty_action_goto_tab_e) {
        let tabs = tabStore.tabs
        guard !tabs.isEmpty else { return }

        let rawValue = tabIndex.rawValue
        switch rawValue {
        case GHOSTTY_GOTO_TAB_PREVIOUS.rawValue:
            // Previous tab
            if let activeID = tabStore.activeTabID,
               let currentIndex = tabs.firstIndex(where: { $0.id == activeID }),
               currentIndex > 0 {
                tabStore.activeTabID = tabs[currentIndex - 1].id
            }

        case GHOSTTY_GOTO_TAB_NEXT.rawValue:
            // Next tab
            if let activeID = tabStore.activeTabID,
               let currentIndex = tabs.firstIndex(where: { $0.id == activeID }),
               currentIndex < tabs.count - 1 {
                tabStore.activeTabID = tabs[currentIndex + 1].id
            }

        case GHOSTTY_GOTO_TAB_LAST.rawValue:
            // Last tab
            tabStore.activeTabID = tabs.last?.id

        default:
            // Positive values are 1-based tab indices
            let index = Int(rawValue) - 1
            if let tab = tabStore.tab(at: index) {
                tabStore.activeTabID = tab.id
            }
        }
    }

    private func observeSplitActions(_ center: NotificationCenter) {
        center.addObserver(
            forName: Ghostty.Notification.ghosttyNewSplit,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let ghosttyDirection = notification.userInfo?["direction"]
                as? ghostty_action_split_direction_e
            let splitDirection: SplitDirection
            switch ghosttyDirection {
            case GHOSTTY_SPLIT_DIRECTION_LEFT: splitDirection = .left
            case GHOSTTY_SPLIT_DIRECTION_UP: splitDirection = .up
            case GHOSTTY_SPLIT_DIRECTION_DOWN: splitDirection = .down
            default: splitDirection = .right
            }
            self.splitSurface(direction: splitDirection)
        }

        center.addObserver(
            forName: Ghostty.Notification.ghosttyFocusSplit,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let tab = self.tabStore.activeTab,
                  let focusedLeafID = tab.focusedLeafID else { return }
            let direction = notification.userInfo?[
                Ghostty.Notification.SplitDirectionKey
            ] as? Ghostty.SplitFocusDirection

            if let target = focusTarget(
                root: tab.splitRoot, leafID: focusedLeafID,
                direction: direction
            ) {
                tab.focusedLeafID = target.id
                self.updateSurfaceFocus(for: tab)
                if let surfaceView = surfaces[target.surfaceID] {
                    Ghostty.moveFocus(to: surfaceView)
                }
            }
        }
    }

    /// Find the target leaf for a split focus navigation.
    private func focusTarget(
        root: SplitNode, leafID: UUID,
        direction: Ghostty.SplitFocusDirection?
    ) -> SurfaceLeaf? {
        switch direction {
        case .previous:
            return SplitTree.previousLeaf(node: root, before: leafID)
        case .next:
            return SplitTree.nextLeaf(node: root, after: leafID)
        case .left:
            return SplitTree.findNeighbor(node: root, leafID: leafID, direction: .left)
        case .right:
            return SplitTree.findNeighbor(node: root, leafID: leafID, direction: .right)
        case .up:
            return SplitTree.findNeighbor(node: root, leafID: leafID, direction: .up)
        case .down:
            return SplitTree.findNeighbor(node: root, leafID: leafID, direction: .down)
        default:
            return SplitTree.nextLeaf(node: root, after: leafID)
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
            var config = Ghostty.SurfaceConfiguration()
            config.workingDirectory = directories[leaf.id]
            let surfaceView = Ghostty.SurfaceView(app, baseConfig: config)
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
