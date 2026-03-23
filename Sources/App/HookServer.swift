// ABOUTME: Unix domain socket server for Claude Code hook callbacks.
// ABOUTME: Receives state updates (working, waiting, idle) from shell hooks via /tmp/montty-hook.sock.

import AppKit
import Foundation
import os

private let log = Logger(subsystem: "montty", category: "HookServer")

/// Lightweight Unix domain socket listener for Claude Code hook callbacks.
/// Runs in all builds (debug and release) so hooks work in shipped versions.
enum HookServer {
    static let socketPath = "/tmp/montty-hook.sock"
    private nonisolated(unsafe) static var serverFD: Int32 = -1
    private nonisolated(unsafe) static var running = false

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
    /// Body is JSON: {"event": "prompt-submit|notification|stop", "surface": "MONTTY_SURFACE_ID"}
    private static func processHook(_ body: String) {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["event"] as? String,
              let surfaceID = json["surface"] as? String else { return }

        let state: ClaudeCodeStatus.State
        switch event {
        case "prompt-submit": state = .working
        case "notification": state = .waiting
        case "stop": state = .idle
        default: return
        }

        DispatchQueue.main.async {
            guard let delegate = NSApp?.delegate else { return }
            let appDelegate: AppDelegate?
            if let appDel = delegate as? AppDelegate {
                appDelegate = appDel
            } else {
                // With @NSApplicationDelegateAdaptor, NSApp.delegate is a SwiftUI
                // wrapper. Walk its properties to find our actual AppDelegate.
                let mirror = Mirror(reflecting: delegate)
                appDelegate = mirror.children.lazy
                    .compactMap { $0.value as? AppDelegate }.first
            }
            guard let appDelegate else { return }
            for tab in appDelegate.tabStore.tabs {
                tab.claudeStates[surfaceID] = state
            }
        }
    }
}
