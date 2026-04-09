// ABOUTME: Unix domain socket server for Claude Code hook callbacks.
// ABOUTME: Receives state updates (working, waiting, idle) from shell hooks via /tmp/montty-hook.sock.

import AppKit
import Foundation
import os

private let log = Logger(subsystem: "montty", category: "HookServer")

/// A recorded hook event, for diagnostics.
struct HookLogEntry {
    let timestamp: Date
    let event: String
    let surface: String
    let matched: Bool
    /// Resulting state after the event, or nil for rejection / session-end (entry removed).
    let newState: String?
}

/// Lightweight Unix domain socket listener for Claude Code hook callbacks.
/// Runs in all builds (debug and release) so hooks work in shipped versions.
enum HookServer {
    static let socketPath = "/tmp/montty-hook.sock"
    private nonisolated(unsafe) static var serverFD: Int32 = -1
    private nonisolated(unsafe) static var running = false

    // Ring buffer of recent events for diagnostics (exposed via /hook-log).
    private static let logCapacity = 200
    private static let logLock = NSLock()
    private nonisolated(unsafe) static var logBuffer: [HookLogEntry] = []

    /// Returns a snapshot of the most recent hook events (oldest first).
    static func recentEvents() -> [HookLogEntry] {
        logLock.lock()
        defer { logLock.unlock() }
        return logBuffer
    }

    private static func record(_ entry: HookLogEntry) {
        logLock.lock()
        defer { logLock.unlock() }
        logBuffer.append(entry)
        if logBuffer.count > logCapacity {
            logBuffer.removeFirst(logBuffer.count - logCapacity)
        }
    }

    static func start() {
        // Remove stale socket from a previous crash
        unlink(socketPath)

        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            log.error("[HookServer] socket() failed: \(errno)")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { src in
            withUnsafeMutablePointer(to: &addr) { addrPtr in
                let pathPtr = UnsafeMutableRawPointer(addrPtr)
                    .advanced(by: MemoryLayout.offset(of: \sockaddr_un.sun_path)!)
                    .assumingMemoryBound(to: CChar.self)
                _ = strlcpy(pathPtr, src, 104) // sun_path max on macOS
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            log.error("[HookServer] bind() failed: \(errno)")
            close(serverFD)
            serverFD = -1
            return
        }

        guard listen(serverFD, 5) == 0 else {
            log.error("[HookServer] listen() failed: \(errno)")
            close(serverFD)
            serverFD = -1
            return
        }

        running = true
        log.info("[HookServer] Listening on \(socketPath)")

        DispatchQueue.global(qos: .utility).async {
            acceptLoop()
        }
    }

    static func stop() {
        running = false
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        unlink(socketPath)
    }

    private static func acceptLoop() {
        while running {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { break }

            // Read data from client
            var buffer = [UInt8](repeating: 0, count: 65_536)
            let bytesRead = read(clientFD, &buffer, buffer.count)
            close(clientFD)

            if bytesRead > 0 {
                let body = String(bytes: buffer[..<bytesRead], encoding: .utf8) ?? ""
                processHook(body)
            }
        }
    }

    /// Parse a hook JSON message and update tab state.
    /// Body is JSON: {"event": "<name>", "surface": "MONTTY_SURFACE_ID"}
    private static func processHook(_ body: String) {
        guard let message = ClaudeHookMessage.parse(json: body) else {
            log.info("dropped malformed hook body=\(body, privacy: .public)")
            return
        }

        DispatchQueue.main.async {
            guard let appDelegate = findAppDelegate() else { return }

            // Find the tab that owns this MONTTY_SURFACE_ID (check before mutating).
            let owningTab = appDelegate.tabStore.tabs.first { tab in
                tab.surfaceToMonttyID.values.contains(message.surface)
            }

            var newStateLabel: String?
            if let tab = owningTab {
                let outcome = HookStateMachine.apply(
                    message.event,
                    surfaceID: message.surface,
                    to: &tab.claudeStates,
                    waitingSince: &tab.claudeWaitingSince,
                    isKnownSurface: true
                )
                if case .applied(let newState) = outcome {
                    newStateLabel = newState.map { String(describing: $0) }
                }
            }

            let matched = owningTab != nil
            log.info("""
                event=\(message.event.rawValue, privacy: .public) \
                surface=\(message.surface, privacy: .public) \
                matched=\(matched, privacy: .public) \
                newState=\(newStateLabel ?? "nil", privacy: .public)
                """)
            record(HookLogEntry(
                timestamp: Date(),
                event: message.event.rawValue,
                surface: message.surface,
                matched: matched,
                newState: newStateLabel
            ))
        }
    }

    private static func findAppDelegate() -> AppDelegate? {
        NSApp?.delegate as? AppDelegate
    }
}
