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

    override init() {
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

        // Create the initial tab
        createTab()

        // Observe Ghostty action notifications for tab operations
        observeGhosttyActions()

        #if DEBUG
        DebugServer.start()
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
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
    func splitSurface(orientation: SplitOrientation) {
        guard let app = ghostty.app,
              let tab = tabStore.activeTab,
              let focusedLeafID = tab.focusedLeafID else { return }

        let newSurfaceView = Ghostty.SurfaceView(app)
        let newLeafID = UUID()
        surfaces[newSurfaceView.id] = newSurfaceView

        tab.splitRoot = SplitTree.split(
            node: tab.splitRoot,
            leafID: focusedLeafID,
            orientation: orientation,
            newLeafID: newLeafID,
            newSurfaceID: newSurfaceView.id
        )
        tab.focusedLeafID = newLeafID
        observeSurface(newSurfaceView, tab: tab)

        // Move AppKit focus to the new surface after a brief delay
        // to let SwiftUI render the new view hierarchy
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Ghostty.moveFocus(to: newSurfaceView)
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
            .sink { [weak tab] title in
                tab?.autoName = title
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
            let direction = notification.userInfo?["direction"]
                as? ghostty_action_split_direction_e
            let orientation: SplitOrientation =
                (direction == GHOSTTY_SPLIT_DIRECTION_DOWN
                    || direction == GHOSTTY_SPLIT_DIRECTION_UP)
                ? .vertical : .horizontal
            self.splitSurface(orientation: orientation)
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

            let target: SurfaceLeaf?
            switch direction {
            case .previous:
                target = SplitTree.previousLeaf(
                    node: tab.splitRoot, before: focusedLeafID)
            default:
                target = SplitTree.nextLeaf(
                    node: tab.splitRoot, after: focusedLeafID)
            }
            if let target = target {
                tab.focusedLeafID = target.id
                if let surfaceView = surfaces[target.surfaceID] {
                    Ghostty.moveFocus(to: surfaceView)
                }
            }
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
