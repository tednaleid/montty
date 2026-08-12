// ABOUTME: Startup guard: the montty already serving the control socket keeps
// ABOUTME: it, and a second launch raises its windows instead of taking over.

import AppKit
import Foundation
import os

enum InstanceGuard {
    private static let log = Logger(subsystem: "montty", category: "InstanceGuard")

    /// Ends this process when another montty already owns `socketPath`.
    /// Belongs before the window, the session read, and `HookServer.start()`:
    /// binding the socket routes every hook and CLI call to this process, and
    /// loading the session hands its file to a second autosave. The socket path
    /// scopes both steps, so a build with its own `MONTTY_SOCKET` still
    /// launches alongside the installed app.
    ///
    /// The lock goes first, and it is what makes this a guarantee rather than a
    /// good chance. Asking the socket and binding it are roughly 300 ms apart,
    /// and two launches inside that gap both used to pass. Only one process can
    /// hold the lock, so now only one gets that far.
    ///
    /// The probe still runs whenever the lock was not held by someone else,
    /// because it finds the owner the lock cannot: a montty from a build older
    /// than the lock, or one running while the lock file is unusable. The
    /// reverse is not needed. A held lock already proves a live montty, so
    /// there is nothing left for a probe to add.
    static func exitIfAnotherMonttyServes(_ socketPath: String) {
        let lockPath = InstanceLock.path(forSocket: socketPath)
        switch InstanceLock.acquire(path: lockPath) {
        case .acquired:
            break
        case .takenByAnotherProcess:
            yieldToOwner(of: lockPath)
        case .unavailable(let code):
            // Launching unlocked is the safe direction: a lock this process
            // cannot take must never be read as a montty that is not there.
            let reason = String(cString: strerror(code))
            log.notice("""
                cannot lock \(lockPath, privacy: .public) (\(reason, privacy: .public)), \
                launching with the socket probe as the only guard
                """)
        }

        guard ControlProbe.probe(socketPath: socketPath) == .live else { return }
        yieldToOwner(of: socketPath)
    }

    /// Leaves the socket and the session to the montty that already owns them.
    private static func yieldToOwner(of path: String) -> Never {
        log.notice("""
            another montty owns \(path, privacy: .public), \
            exiting rather than taking over its socket and session
            """)
        activateRunningInstance()
        exit(EXIT_SUCCESS)
    }

    /// Best effort: raise every window of the montty already running, which is
    /// what the user asking for another one wants to see. Only one montty can
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
