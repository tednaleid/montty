// ABOUTME: Translates montty's argv into a ControlCommand without touching the
// ABOUTME: environment or the network, so the whole grammar is unit-testable.

import Foundation

enum ParsedInvocation: Equatable {
    case control(ControlCommand)
    /// A setting named with no value: print what that scope resolves to.
    case read(SettingRead)
    /// A Claude Code hook event name, forwarded on the legacy wire format,
    /// with the version of the installed entry that ran it, when it says.
    case hook(event: String, hooksVersion: Int?)
    case installHooks(HookAgent)
    case uninstallHooks(HookAgent)
    case version
}

/// An agent whose own settings `montty install-hooks` knows how to edit.
enum HookAgent: String, Equatable, CaseIterable {
    case claude
}

enum ExitCode: Int32 {
    // swiftlint:disable:next identifier_name
    case ok = 0
    case rejected = 1
    case notInPane = 2
    case notRunning = 3
    case usage = 64
}

enum ControlArgs {
    /// What to print and exit with when argv is not a command to run: help
    /// that was asked for (exit 0), or a usage error (exit 64).
    struct ParseExit: Error, Equatable {
        let message: String
        let exitCode: Int32
    }

    /// Flags montty answers itself. Every other flag belongs to macOS.
    private static let ownFlags: Set<String> = ["--version", "-v", "--help", "-h"]

    /// True when montty should handle these arguments as a command rather than
    /// launch the GUI. Any first argument that is not a flag is montty's own
    /// grammar, so a mistyped verb becomes a usage error instead of a second
    /// app instance fighting the first over the socket and the session file.
    /// Flags montty does not define are macOS launch arguments
    /// (`-psn_0_12345`, `-NSDocumentRevisionsDebugMode`), and those launch the
    /// GUI, as does an empty argument list.
    static func isInvocation(_ arguments: [String]) -> Bool {
        guard let first = arguments.first else { return false }
        guard first.hasPrefix("-") else { return true }
        return ownFlags.contains(first)
    }

    /// The version flags and `hook` are answered here. Everything else goes
    /// to the command declarations in `CLI`.
    static func parse(_ arguments: [String]) -> Result<ParsedInvocation, ParseExit> {
        if arguments == ["--version"] || arguments == ["-v"] {
            return .success(.version)
        }
        if arguments.first == "hook" {
            return parseHook(arguments)
        }
        return CLI.parse(arguments)
    }

    /// A hook runs on every event of an agent session and must never print,
    /// so it is parsed here, where no argument can turn into help text.
    private static func parseHook(_ arguments: [String]) -> Result<ParsedInvocation, ParseExit> {
        guard arguments.count >= 2 else {
            return .failure(ParseExit(
                message: "Error: hook needs an event\nUsage: montty hook <event>",
                exitCode: ExitCode.usage.rawValue
            ))
        }
        return .success(.hook(event: arguments[1], hooksVersion: hooksVersion(in: arguments)))
    }

    /// Hook entries are written by whichever montty installed them, which can
    /// be newer than the one running, so `hook` reads `--hooks-version` and
    /// skips every argument it does not know rather than failing a hook.
    private static func hooksVersion(in arguments: [String]) -> Int? {
        guard let flag = arguments.firstIndex(of: "--hooks-version"), flag + 1 < arguments.count else {
            return nil
        }
        return Int(arguments[flag + 1])
    }
}
