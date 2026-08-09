// ABOUTME: The montty command-line client, reached from main.swift when argv
// ABOUTME: looks like a command rather than an app launch. Talks to MONTTY_SOCKET.

import Foundation

enum ControlCLI {
    static func run(arguments: [String]) -> Never {
        let invocation = parseOrExit(arguments)

        if case .version = invocation {
            print(version())
            exit(ExitCode.ok.rawValue)
        }

        let environment = ProcessInfo.processInfo.environment
        guard let surface = environment["MONTTY_SURFACE_ID"], !surface.isEmpty else {
            // A hook fired outside montty is normal, not an error worth surfacing to
            // Claude Code.
            if case .hook = invocation { exit(ExitCode.ok.rawValue) }
            fail("not running inside a montty pane", .notInPane)
        }

        let socketPath = environment["MONTTY_SOCKET"]
            ?? NSTemporaryDirectory() + "montty-hook.sock"

        switch invocation {
        case .version:
            fatalError("version already exited above; no surface is required for it")
        case .hook(let event):
            runHook(event: event, surface: surface, socketPath: socketPath)
        case .control(let command):
            runControl(command: command, surface: surface, socketPath: socketPath)
        }
    }

    /// The app's own marketing version, falling back only when the bundle
    /// genuinely has none (an unbundled or malformed build).
    private static func version() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "montty (development build)"
    }

    /// Parses argv into an invocation, exiting with the usage error text on
    /// any failure so every caller sees a fully resolved grammar.
    private static func parseOrExit(_ arguments: [String]) -> ParsedInvocation {
        switch ControlArgs.parse(arguments) {
        case .success(let parsed):
            return parsed
        case .failure(let error):
            let detail: String
            switch error {
            case .noArguments: detail = "no arguments"
            case .unknownScope(let value): detail = "unknown scope \"\(value)\""
            case .unknownProperty(let value): detail = "unknown property \"\(value)\""
            case .unknownStatus(let value): detail = "unknown status \"\(value)\""
            case .missingValue(let value): detail = "\(value) needs a value"
            case .badColor(let value): detail = "not a color: \"\(value)\" (use a palette name or #rrggbb)"
            case .tooManyStops: detail = "at most \(PaneTint.maxStops) comma-separated stops"
            }
            fail("\(detail)\n\n\(ControlArgs.usage)", .usage)
        }
    }

    /// Claude Code delivers its payload on stdin; forward the cwd it reports.
    /// Best effort: never make a montty-less environment look broken.
    private static func runHook(event: String, surface: String, socketPath: String) -> Never {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let cwd = (try? JSONSerialization.jsonObject(with: input))
            .flatMap { ($0 as? [String: Any])?["cwd"] as? String }
        var message: [String: Any] = ["event": event, "surface": surface]
        if let cwd, !cwd.isEmpty { message["cwd"] = cwd }
        if let payload = try? JSONSerialization.data(withJSONObject: message) {
            _ = roundTrip(payload, socketPath: socketPath, expectReply: false)
        }
        exit(ExitCode.ok.rawValue)
    }

    private static func runControl(command: ControlCommand, surface: String, socketPath: String) -> Never {
        let request = ControlRequest(surface: surface, command: command)
        guard let payload = try? request.encoded() else {
            fail("could not encode the request", .usage)
        }
        guard let reply = roundTrip(payload, socketPath: socketPath, expectReply: true),
              !reply.isEmpty else {
            fail("montty is not running", .notRunning)
        }

        let parsed = (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any]
        guard parsed?["ok"] as? Bool == true else {
            fail(parsed?["error"] as? String ?? "request rejected", .rejected)
        }
        if case .info = command {
            FileHandle.standardOutput.write(reply)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        exit(ExitCode.ok.rawValue)
    }

    private static func fail(_ message: String, _ code: ExitCode) -> Never {
        FileHandle.standardError.write(Data("montty: \(message)\n".utf8))
        exit(code.rawValue)
    }

    /// Open the socket, send `payload`, and read the reply until EOF. Returns nil
    /// when montty is not reachable.
    private static func roundTrip(_ payload: Data, socketPath: String, expectReply: Bool) -> Data? {
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        // A missing or wedged socket should fail fast, so the send side keeps
        // a tight timeout. The receive side has to outlast HookServer's own
        // 2s main-thread ceiling (applyOnMain), or a montty that is merely
        // busy -- and about to reply with its own timeout error -- reads as
        // "not running" instead.
        var sendTimeout = timeval(tv_sec: 1, tv_usec: 0)
        var recvTimeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &recvTimeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { src in
            withUnsafeMutablePointer(to: &addr) { addrPtr in
                let pathPtr = UnsafeMutableRawPointer(addrPtr)
                    .advanced(by: MemoryLayout.offset(of: \sockaddr_un.sun_path)!)
                    .assumingMemoryBound(to: CChar.self)
                _ = strlcpy(pathPtr, src, 104)
            }
        }

        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }

        var sent = 0
        payload.withUnsafeBytes { raw in
            while sent < raw.count {
                let written = write(sock, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                if written <= 0 { break }
                sent += written
            }
        }
        guard sent == payload.count else { return nil }
        guard expectReply else { return Data() }

        var reply = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(sock, &buffer, buffer.count)
            if count <= 0 { break }
            reply.append(contentsOf: buffer[..<count])
        }
        return reply
    }
}
