import Cocoa
import GhosttyKit
import os
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, GhosttyAppDelegate, ObservableObject {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.montty.app",
        category: "app"
    )

    @Published var ghostty: Ghostty.App

    /// UndoManager accessed by Ghostty.App.swift for undo/redo routing
    let undoManager: UndoManager? = nil

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

    // MARK: - GhosttyAppDelegate

    func findSurface(forUUID uuid: UUID) -> Ghostty.SurfaceView? {
        // Phase 1: no surface tracking yet
        return nil
    }

    // MARK: - Interface expected by Ghostty binding files

    // SurfaceView_AppKit.swift calls this to handle Ghostty keybinding menu equivalents
    func performGhosttyBindingMenuKeyEquivalent(with event: NSEvent) -> Bool {
        return false
    }

    // Ghostty.App.swift action handlers call these on AppDelegate by name
    func checkForUpdates(_ sender: Any?) {}
    func closeAllWindows(_ sender: Any?) {}
    func toggleVisibility(_ sender: Any?) {}
    func toggleQuickTerminal(_ sender: Any?) {}
    func setSecureInput(_ mode: Ghostty.SetSecureInput) {}
    func syncFloatOnTopMenu(_ window: NSWindow) {}
}
