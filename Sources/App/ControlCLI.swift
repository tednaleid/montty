// ABOUTME: The montty command-line client, reached from main.swift when argv
// ABOUTME: looks like a command rather than an app launch. Talks to MONTTY_SOCKET.

import Foundation

enum ControlCLI {
    static func run(arguments: [String]) -> Never {
        // A montty that closes the connection mid-write has to read as an
        // error, not as a killed process. The process-wide ignore ghostty_init
        // installs is not in play here: this path never creates NSApplication.
        signal(SIGPIPE, SIG_IGN)

        let invocation = parseOrExit(arguments)

        if case .version = invocation {
            print(version())
            exit(ExitCode.ok.rawValue)
        }
        if case .help = invocation {
            print(ControlArgs.usage)
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
        case .version, .help:
            fatalError("version and help already exited above; neither needs a surface")
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
            case .unexpectedArgument(let value):
                detail = "unexpected argument \"\(value)\"; quote a value that contains spaces"
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
            _ = ControlTransport.roundTrip(payload, socketPath: socketPath, expectReply: false)
        }
        exit(ExitCode.ok.rawValue)
    }

    private static func runControl(command: ControlCommand, surface: String, socketPath: String) -> Never {
        let request = ControlRequest(surface: surface, command: command)
        guard let payload = try? request.encoded() else {
            fail("could not encode the request", .usage)
        }
        guard payload.count <= ControlTransport.maxRequestBytes else {
            fail("request is larger than \(ControlTransport.maxRequestBytes) bytes", .usage)
        }

        let reply: Data
        switch ControlTransport.roundTrip(payload, socketPath: socketPath, expectReply: true) {
        case .success(let data) where !data.isEmpty:
            reply = data
        case .success:
            fail(ControlTransportError.disconnected.message, .notRunning)
        case .failure(let error):
            fail(error.message, .notRunning)
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
}
