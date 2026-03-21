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
        surfaceObservers.removeValue(forKey: tab.surfaceID)
        surfaces.removeValue(forKey: tab.surfaceID)
        tabStore.close(id: id)

        // If no tabs remain, quit
        if tabStore.tabs.isEmpty {
            NSApplication.shared.terminate(nil)
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
