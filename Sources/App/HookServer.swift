// ABOUTME: Unix domain socket server for Claude Code hook callbacks.
// ABOUTME: Receives state updates (working, waiting, idle) from shell hooks via a per-user socket.

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
    /// Per-user, mode 0700, and auto-cleaned. `MONTTY_SOCKET` overrides it so a
    /// dev build never rebinds the installed app's socket, mirroring
    /// MONTTY_SESSION_DIR.
    static let socketPath = ProcessInfo.processInfo.environment["MONTTY_SOCKET"]
        ?? NSTemporaryDirectory() + "montty-hook.sock"
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

        var addr = ControlTransport.address(for: socketPath)

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

        // A backlog only has to outlast the accept loop's turnaround, but a
        // short one turns a burst of hooks and CLI calls across panes into
        // refused connections, which the CLI cannot tell from a montty that
        // is not running.
        guard listen(serverFD, SOMAXCONN) == 0 else {
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

    private static let handlerQueue = DispatchQueue(
        label: "montty.hookserver.handler", attributes: .concurrent
    )

    private static func acceptLoop() {
        while running {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { break }
            handlerQueue.async { handleConnection(clientFD) }
        }
    }

    private static func handleConnection(_ clientFD: Int32) {
        defer { close(clientFD) }

        // Bounds how long a peer can hold a handler thread: one that opens but
        // sends nothing, and one that sends a request and never reads the
        // reply. Without these, enough such connections exhaust the handler
        // pool and block hook delivery. ControlTransport bounds the read as a
        // whole; these bound each call.
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(clientFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let data: Data
        switch ControlTransport.readRequest(from: clientFD) {
        case .empty:
            return
        case .tooLarge:
            reply(
                .failure("request is larger than \(ControlTransport.maxRequestBytes) bytes"),
                to: clientFD
            )
            return
        case .request(let bytes):
            data = bytes
        }

        // A liveness ping is answered here rather than decoded: it names no
        // surface, so request decoding would call it malformed, and answering
        // from this thread keeps the answer honest while main is busy.
        if ControlPing.isRequest(data) {
            reply(.ok, to: clientFD)
            return
        }

        let response: ControlResponse
        do {
            let request = try ControlRequest.decode(data)
            response = applyOnMain(request)
        } catch ControlRequest.DecodeFailure.legacyHook {
            processHook(String(bytes: data, encoding: .utf8) ?? "")
            return
        } catch ControlRequest.DecodeFailure.unsupportedVersion {
            response = .failure("montty CLI is newer than the app")
        } catch ControlRequest.DecodeFailure.nameTooLong {
            response = .failure(
                "tab name is longer than \(ControlWire.maxNameCharacters) characters"
            )
        } catch {
            response = .failure("malformed request")
        }

        reply(response, to: clientFD)
    }

    private static func reply(_ response: ControlResponse, to clientFD: Int32) {
        if let out = try? response.encoded() {
            out.withUnsafeBytes { _ = write(clientFD, $0.baseAddress, $0.count) }
        }
    }

    /// Model mutation happens on main. A 2s ceiling keeps a wedged main thread
    /// from pinning a handler thread forever.
    private static func applyOnMain(_ request: ControlRequest) -> ControlResponse {
        let semaphore = DispatchSemaphore(value: 0)
        var response: ControlResponse = .failure("montty did not respond")

        DispatchQueue.main.async {
            defer { semaphore.signal() }
            guard let appDelegate = findAppDelegate(),
                  let tab = appDelegate.tabStore.tabs.first(where: { tab in
                      tab.surfaceToMonttyID.values.contains(request.surface)
                  }),
                  let surfaceID = tab.surfaceToMonttyID.first(
                      where: { $0.value == request.surface }
                  )?.key else {
                response = .failure(ControlError.unknownSurface.rawValue)
                return
            }
            switch appDelegate.applyControl(request.command, to: tab, surfaceID: surfaceID) {
            case .applied: response = .ok
            case .read(let info): response = .info(info)
            case .rejected(let error): response = .failure(error.rawValue)
            }
        }

        if semaphore.wait(timeout: .now() + 2) == .timedOut {
            // The queued main-thread block still holds a reference to
            // `response` and may write it after this point, so the timeout
            // path must return a fresh value rather than reading the
            // variable it could race with.
            return .failure("montty did not respond")
        }
        return response
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
                    to: &tab.activityStates,
                    waitingSince: &tab.activityWaitingSince,
                    isKnownSurface: true
                )
                if case .applied(let newState) = outcome {
                    newStateLabel = newState.map(\.wireName)
                }
                HookDirectoryTracker.apply(
                    event: message.event,
                    surfaceID: message.surface,
                    cwd: message.cwd,
                    to: &tab.claudeDirectories
                )
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
