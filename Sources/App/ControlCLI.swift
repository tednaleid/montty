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
        runIfPaneless(invocation)

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
        case .version, .installHooks, .uninstallHooks:
            fatalError("\(invocation) already exited above; it needs no surface")
        case .read(let read):
            runRead(read, surface: surface, socketPath: socketPath)
        case .hook(let event, let hooksVersion):
            runHook(event: event, hooksVersion: hooksVersion, surface: surface, socketPath: socketPath)
        case .control(let command):
            runControl(command: command, surface: surface, socketPath: socketPath)
        }
    }

    /// Runs and exits for the invocations that need no montty pane; returns
    /// for every other one.
    private static func runIfPaneless(_ invocation: ParsedInvocation) {
        switch invocation {
        case .version:
            print(version())
            exit(ExitCode.ok.rawValue)
        case .installHooks(let agent):
            runHookSettings(agent: agent, install: true)
        case .uninstallHooks(let agent):
            runHookSettings(agent: agent, install: false)
        case .control, .read, .hook:
            return
        }
    }

    /// The app's own marketing version, falling back only when the bundle
    /// genuinely has none (an unbundled or malformed build).
    private static func version() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "montty (development build)"
    }

    /// Parses argv into an invocation. Help that was asked for prints to
    /// stdout and exits 0; a usage error prints to stderr and exits 64.
    private static func parseOrExit(_ arguments: [String]) -> ParsedInvocation {
        switch ControlArgs.parse(arguments) {
        case .success(let parsed):
            return parsed
        case .failure(let parseExit):
            let output = parseExit.exitCode == ExitCode.ok.rawValue
                ? FileHandle.standardOutput : FileHandle.standardError
            output.write(Data("\(parseExit.message)\n".utf8))
            exit(parseExit.exitCode)
        }
    }

    /// Claude Code delivers its payload on stdin; forward the cwd, session id,
    /// and end reason it reports, for interactive sessions only. At session
    /// start, tell the user when the installed entries are out of date. Best
    /// effort: never make a montty-less environment look broken.
    private static func runHook(event: String, hooksVersion: Int?, surface: String, socketPath: String) -> Never {
        let entrypoint = ProcessInfo.processInfo.environment["CLAUDE_CODE_ENTRYPOINT"]
        guard ClaudeHooks.reportsSession(entrypoint: entrypoint) else { exit(ExitCode.ok.rawValue) }
        if event == "session-start", let reply = ClaudeHooks.sessionStartReply(installedVersion: hooksVersion) {
            print(reply)
        }
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let payload = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any]
        var message: [String: Any] = ["event": event, "surface": surface]
        for key in ["cwd", "session_id", "reason"] {
            if let value = payload?[key] as? String, !value.isEmpty { message[key] = value }
        }
        if let payload = try? JSONSerialization.data(withJSONObject: message) {
            _ = ControlTransport.roundTrip(payload, socketPath: socketPath, expectReply: false)
        }
        exit(ExitCode.ok.rawValue)
    }

    /// Adds or removes montty's hooks in Claude Code's user settings. Runs from
    /// any terminal, since it only edits a file. The previous file is kept
    /// next to it as a backup whenever it changes.
    private static func runHookSettings(agent: HookAgent, install: Bool) -> Never {
        let url = claudeSettingsURL()
        let original = FileManager.default.contents(atPath: url.path)
        var settings = JSONValue.object([])
        if let original {
            guard let text = String(data: original, encoding: .utf8),
                  let parsed = JSONValue.parse(text), case .object = parsed else {
                fail("\(url.path) is not a JSON object; left it unchanged", .rejected)
            }
            settings = parsed
        }
        let updated = install
            ? ClaudeHooks.installing(into: settings)
            : ClaudeHooks.uninstalling(from: settings)

        if updated == settings && (original != nil || !install) {
            print(install ? "montty hooks already current in \(url.path)" : "no montty hooks in \(url.path)")
            exit(ExitCode.ok.rawValue)
        }
        let endsWithNewline = original.map { $0.last == UInt8(ascii: "\n") } ?? true
        let output = updated.formatted() + (endsWithNewline ? "\n" : "")
        writeSettings(Data(output.utf8), to: url, replacing: original)
        if install {
            print("installed montty hooks version \(ClaudeHooks.version) in \(url.path)")
            print("Claude sessions started from now on report to montty; restart running ones to include them")
        } else {
            print("removed montty hooks from \(url.path)")
        }
        exit(ExitCode.ok.rawValue)
    }

    /// Claude Code's user settings file, honoring CLAUDE_CONFIG_DIR as Claude
    /// does. A symlinked file is written through, so a settings file kept in a
    /// dotfiles repository stays a link.
    private static func claudeSettingsURL() -> URL {
        let configured = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? ""
        let directory = configured.isEmpty ? NSHomeDirectory() + "/.claude" : configured
        return URL(fileURLWithPath: directory)
            .appendingPathComponent("settings.json")
            .resolvingSymlinksInPath()
    }

    private static func writeSettings(_ output: Data, to url: URL, replacing original: Data?) {
        do {
            if let original {
                try original.write(to: URL(fileURLWithPath: url.path + ".montty-backup"), options: .atomic)
            }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try output.write(to: url, options: .atomic)
        } catch {
            fail("could not write \(url.path): \(error.localizedDescription)", .rejected)
        }
    }

    /// Reads a setting back through the info command, so no wire verb is
    /// needed per setting. A setting with nothing to report prints nothing.
    private static func runRead(_ read: SettingRead, surface: String, socketPath: String) -> Never {
        let info = requestInfo(surface: surface, socketPath: socketPath)
        if let text = SettingReadout.text(read, info: info) {
            print(text)
        }
        exit(ExitCode.ok.rawValue)
    }

    /// The info reply as a raw dictionary. `ControlInfo` is not decoded here:
    /// it is encoded with a snake-case strategy that renders `surfaceID` as
    /// `surface_id`, and the matching decode strategy restores that as
    /// `surfaceId`, which no longer matches the property.
    private static func requestInfo(surface: String, socketPath: String) -> [String: Any] {
        let request = ControlRequest(surface: surface, command: .info)
        guard let payload = try? request.encoded() else {
            fail("could not encode the request", .usage)
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
        guard let parsed, parsed["ok"] as? Bool == true else {
            fail(parsed?["error"] as? String ?? "request rejected", .rejected)
        }
        return parsed
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
