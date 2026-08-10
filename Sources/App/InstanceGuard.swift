// ABOUTME: Startup guard: the montty already serving the control socket keeps
// ABOUTME: it, and a second launch raises that window instead of taking over.

import AppKit
import Foundation
import os

enum InstanceGuard {
    private static let log = Logger(subsystem: "montty", category: "InstanceGuard")

    /// Ends this process when a live montty answers on `socketPath`. Belongs
    /// before the window, the session read, and `HookServer.start()`: binding
    /// the socket routes every hook and CLI call to this process, and loading
    /// the session hands its file to a second autosave. The socket path scopes
    /// the guard, so a build with its own `MONTTY_SOCKET` still launches
    /// alongside the installed app.
    static func exitIfAnotherMonttyServes(_ socketPath: String) {
        guard ControlProbe.probe(socketPath: socketPath) == .live else { return }
        log.notice("""
            another montty owns \(socketPath, privacy: .public), \
            exiting rather than taking over its socket and session
            """)
        activateRunningInstance()
        exit(EXIT_SUCCESS)
    }

    /// Best effort: raise the window the user asked for. Only one montty can
    /// own the socket, so more than one candidate means the owner is not
    /// identified, and nothing is activated.
    private static func activateRunningInstance() {
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard others.count == 1, let owner = others.first else { return }
        _ = owner.activate(options: [.activateAllWindows])
    }
}
