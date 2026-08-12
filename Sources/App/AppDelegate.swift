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

    /// Surface jump mode state (nil = normal mode).
    @Published var jumpState: JumpState?

    /// Whether the sidebar is visible.
    @Published var sidebarVisible = true

    /// Whether surface background tinting is enabled.
    @Published var surfaceTintEnabled = true
    /// Per-repo/worktree color overrides, keyed by repo identity string.
    @Published var repoColorOverrides: [String: PaneTint] = [:]
    /// ANSI palette colors from the Ghostty config (14 colors, reordered).
    /// Indexed by TabColor.orderedCases position. Empty before config loads.
    var tabPalette: [NSColor] = []

    let registry = WindowRegistry()
    var controllers: [UUID: WindowController] = [:]

    var keyController: WindowController? {
        guard let id = registry.keyWindow?.id else { return nil }
        return controllers[id]
    }

    /// The tabs of the window holding focus.
    var tabStore: TabStore {
        registry.keyWindow?.tabStore ?? TabStore()
    }

    /// The window holding focus.
    var window: NSWindow? {
        keyController?.window
    }

    static func shared() -> AppDelegate? {
        NSApp?.delegate as? AppDelegate
    }

    /// UndoManager accessed by Ghostty.App.swift for undo/redo routing
    let undoManager: UndoManager? = nil

    /// Surface views keyed by surface UUID. SwiftUI can't hold NSView
    /// references in the model layer, so AppDelegate owns them. Not private:
    /// `AppDelegate+WindowLifecycle.swift` forgets a closing window's entries.
    var surfaces: [UUID: Ghostty.SurfaceView] = [:]

    /// Combine subscriptions for surface property observation. Not private,
    /// for the same reason `surfaces` isn't.
    var surfaceObservers: [UUID: Set<AnyCancellable>] = [:]

    /// Tick timer for the Ghostty event loop
    private var tickTimer: Timer?
    private var claudeWaitingTimer: Timer?

    /// NSEvent monitor for capturing keys during jump mode
    private var jumpKeyMonitor: Any?

    /// Session persistence. Not private: `AppDelegate+WindowLifecycle.swift`
    /// saves through this on every window close.
    let sessionStore = SessionStore()

    /// Set once an app-wide quit is underway. AppKit closes every open window
    /// as part of `terminate(_:)`, each running through `windowWillClose` --
    /// without this flag, whichever window happens to close last would look
    /// like an ordinary "last window closing" and overwrite the complete
    /// snapshot `applicationShouldTerminate` already saved with a snapshot of
    /// just itself. Never cleared once set; see `applicationShouldTerminate`.
    /// Not private, for the same reason `sessionStore` isn't.
    var isTerminating = false

    /// The last complete, non-empty snapshot `applicationShouldTerminate`
    /// captured for a real app-wide quit, kept in memory as a second,
    /// independent guard beside `isTerminating`: the close path refuses to
    /// write an empty snapshot while this is set, even if `isTerminating`
    /// were somehow wrong. `nil` means no quit has ever been requested in
    /// this process, so an empty snapshot from a window closed by hand is
    /// exactly what belongs on disk. Not private, for the same reason
    /// `sessionStore` isn't.
    var lastQuitSnapshot: SessionSnapshot?

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
        NSApp.activate()

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

        // Restore every saved window, or open one fresh tab when there is
        // nothing to restore -- restoreSession owns all startup window
        // creation, so a saved multi-window session doesn't also get an
        // extra blank window from here.
        restoreSession(sessionStore.load() ?? SessionSnapshot())

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

        // Sweep stale Claude `.waiting` states every 5 seconds. Safety net
        // against lost hook events leaving `*?` stuck on the minimap.
        claudeWaitingTimer = Timer.scheduledTimer(
            withTimeInterval: 5.0, repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            for tab in self.tabStore.tabs {
                tab.sweepStaleWaiting()
            }
        }
    }

    /// Save every open window before AppKit starts closing them one by one as
    /// part of quitting. Skipped when nothing is open, which happens when
    /// this fires as a side effect of `windowWillClose` requesting the quit
    /// after the last window already closed and saved itself.
    ///
    /// `isTerminating` is never cleared once set (see its declaration): a
    /// stranded `true` after a quit the system cancels costs at most a
    /// skipped save on some later window close, while clearing it wrongly
    /// mid-quit -- which an activation firing between this call and AppKit
    /// closing windows one by one cannot be ruled out -- risks the close
    /// path overwriting this save with an empty one. Stranding is the
    /// cheaper failure, so nothing clears the flag.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isTerminating = true
        if !registry.windows.isEmpty {
            let snapshot = createSnapshot()
            sessionStore.save(snapshot: snapshot)
            lastQuitSnapshot = snapshot
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionStore.stopAutoSave()

        HookServer.stop()
        #if DEBUG
        DebugServer.stop()
        #endif

        tickTimer?.invalidate()
        tickTimer = nil
        claudeWaitingTimer?.invalidate()
        claudeWaitingTimer = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - Tab lifecycle

    /// Port for the debug HTTP server (debug builds only).
    static let hookPort = 9876

    /// The app's own executable, which also answers to the montty CLI
    /// grammar, so a pane can reach it by absolute path regardless of PATH.
    static let binPath = Bundle.main.executableURL?.path ?? ""

    func createTab() {
        guard let app = ghostty.app else { return }
        let monttyID = UUID().uuidString
        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = focusedDirectory(of: tabStore.activeTab)
        config.environmentVariables["MONTTY_SURFACE_ID"] = monttyID
        config.environmentVariables["MONTTY_PORT"] = String(Self.hookPort)
        config.environmentVariables["MONTTY_SOCKET"] = HookServer.socketPath
        config.environmentVariables["MONTTY_BIN"] = Self.binPath
        let surfaceView = Ghostty.SurfaceView(app, baseConfig: config)
        let tab = Tab(surfaceID: surfaceView.id)
        tab.surfaceToMonttyID[surfaceView.id] = monttyID
        surfaces[surfaceView.id] = surfaceView
        tabStore.append(tab: tab)
        tabStore.activeTabID = tab.id

        // Watch for title and PWD changes from this surface
        observeSurface(surfaceView, tab: tab)

        // A surface is born with `focused == true`, so blur the tabs it displaced.
        syncSurfaceFocus()
    }

    func closeTab(id: UUID) {
        guard let tab = tabStore.tabs.first(where: { $0.id == id }) else { return }
        // Resolved up front, not assumed to be the key window: the tabStore
        // this function reads is a scaffold that currently always resolves to
        // the key window, but the window actually owning this tab is what
        // must close if this turns out to be its last one.
        let owningWindow = registry.locate(tabID: id).flatMap { controllers[$0.id] }
        // Clean up all surfaces in this tab's split tree
        for surfaceID in tab.allSurfaceIDs {
            surfaceObservers.removeValue(forKey: surfaceID)
            surfaces.removeValue(forKey: surfaceID)
        }
        tabStore.close(id: id)

        // If no tabs remain in this window, close the window through the same
        // teardown windowWillClose uses. Quitting is windowWillClose's call,
        // made only when this was the last window.
        //
        // Deferred a run loop turn: this can run from a Ghostty action on the
        // surface that just closed, and closing the window synchronously can
        // tear down that surface's view while it is still on the call stack
        // that invoked us. Closing on the next turn lets that stack unwind.
        if tabStore.tabs.isEmpty {
            let windowToClose = owningWindow?.window
            DispatchQueue.main.async {
                windowToClose?.close()
            }
            return
        }
        syncSurfaceFocus()
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
        config.workingDirectory = focusedDirectory(of: tab)
        config.environmentVariables["MONTTY_SURFACE_ID"] = monttyID
        config.environmentVariables["MONTTY_PORT"] = String(Self.hookPort)
        config.environmentVariables["MONTTY_SOCKET"] = HookServer.socketPath
        config.environmentVariables["MONTTY_BIN"] = Self.binPath
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
        syncSurfaceFocus()
        if let surfaceID = tab.focusedSurfaceID,
           let surfaceView = surfaces[surfaceID] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Ghostty.moveFocus(to: surfaceView)
            }
        }
    }

    /// Push the focus policy out to every surface in every window. The only
    /// place montty calls `focusDidChange`, which updates both the Swift-side
    /// flag and the C-side `ghostty_surface_set_focus`.
    ///
    /// Each window's plan reads that window's own live `isKeyWindow`, not the
    /// registry's `keyWindowID` -- a window in the middle of resigning key is
    /// already reporting `isKeyWindow == false` even if `keyWindowID` was
    /// reassigned to another window earlier in the same call stack, so the
    /// resigning window's surfaces still blur correctly.
    ///
    /// Blurs run before focuses, across every window in one pass. libghostty
    /// writes the DEC mode 1004 reports in call order, and an outgoing surface
    /// must see its blur before any incoming surface sees its focus.
    func syncSurfaceFocus() {
        var plan: [UUID: Bool] = [:]
        for windowModel in registry.windows {
            let isKey = controllers[windowModel.id]?.window.isKeyWindow ?? false
            plan.merge(SurfaceFocus.plan(
                tabs: windowModel.tabStore.tabs,
                activeTabID: windowModel.tabStore.activeTabID,
                windowIsKey: isKey
            )) { _, new in new }
        }
        for (surfaceID, focused) in plan where !focused {
            surfaces[surfaceID]?.focusDidChange(false)
        }
        for (surfaceID, focused) in plan where focused {
            surfaces[surfaceID]?.focusDidChange(true)
        }
    }

    func surfaceView(for surfaceID: UUID) -> Ghostty.SurfaceView? {
        surfaces[surfaceID]
    }

    /// Wires a freshly created surface into surface lookup and change
    /// observation.
    func registerSurface(_ surfaceView: Ghostty.SurfaceView, tab: Tab, monttyID: String) {
        tab.surfaceToMonttyID[surfaceView.id] = monttyID
        surfaces[surfaceView.id] = surfaceView
        observeSurface(surfaceView, tab: tab)
    }

    /// The shell's working directory for a tab's focused surface. New tabs and
    /// splits inherit it so they open where you were, not where libghostty last
    /// tracked.
    private func focusedDirectory(of tab: Tab?) -> String? {
        guard let surfaceID = tab?.focusedSurfaceID else { return nil }
        return surfaces[surfaceID]?.pwd
    }

    /// Move the first responder to the active tab's focused surface, if any.
    func focusActiveSurface() {
        if let surfaceID = tabStore.activeTab?.focusedSurfaceID,
           let surfaceView = surfaceView(for: surfaceID) {
            Ghostty.moveFocus(to: surfaceView)
        }
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
                // Safety net: a title change is strong evidence Claude is active,
                // so clear any stuck `.waiting` state on this surface.
                tab?.clearWaitingOnTitleChange(for: id)
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

    // MARK: - Control

    /// The single write path into styling state. Every driving adapter -- the
    /// CLI, the context menu, and the Claude hooks -- comes through here.
    @discardableResult
    func applyControl(_ command: ControlCommand, to tab: Tab, surfaceID: UUID) -> ControlResult {
        tab.applyControl(
            command, surfaceID: surfaceID, repoColorOverrides: &repoColorOverrides
        )
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

    // MARK: - GhosttyAppDelegate

    func findSurface(forUUID uuid: UUID) -> Ghostty.SurfaceView? {
        surfaces[uuid]
    }

    // MARK: - Interface expected by Ghostty binding files

    func performGhosttyBindingMenuKeyEquivalent(with event: NSEvent) -> Bool {
        return false
    }

    func checkForUpdates(_ sender: Any?) {}
    func toggleVisibility(_ sender: Any?) {}
    func toggleQuickTerminal(_ sender: Any?) {}
    func setSecureInput(_ mode: Ghostty.SetSecureInput) {}
    func syncFloatOnTopMenu(_ window: NSWindow) {}
}
