// ABOUTME: Translates montty's argv into a ControlCommand without touching the
// ABOUTME: environment or the network, so the whole grammar is unit-testable.

import Foundation

enum ParsedInvocation: Equatable {
    case control(ControlCommand)
    /// `montty <scope> color` with no value: print what that scope resolves to.
    case showColor(ControlScope)
    /// A Claude Code hook event name, forwarded on the legacy wire format.
    case hook(String)
    case version
    case help
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
    enum UsageError: Error, Equatable {
        case noArguments
        case unknownScope(String)
        case unknownProperty(String)
        case unknownStatus(String)
        case missingValue(String)
        case badColor(String)
        case tooManyStops
        case badTintStrength(String)
        case unexpectedArgument(String)
    }

    static var usage: String {
        """
        usage: montty <scope> <property> <value>

          montty surface color <spec>      montty surface color --reset
          montty tab     color <spec>      montty tab     color --reset
          montty repo    color <spec>      montty repo    color --reset
          montty <scope> color             prints what that scope resolves to
          montty tab     name  <text>      montty tab     name  --reset
          montty surface status <working|waiting|idle|clear>
          montty hook <event>
          montty tint-strength <value>     montty tint-strength --reset
          montty info
          montty --version                 montty -v
          montty --help                    montty -h

        <spec> is 1 to 3 comma-separated stops. A stop is a palette name
        (green, brightMagenta, neutralBright) or a six-digit hex value with
        or without a leading #.

        <value> for tint-strength is between \(SurfaceTintStrength.range.lowerBound) and \
        \(SurfaceTintStrength.range.upperBound); the default is \(SurfaceTintStrength.default).

        palette names:
        \(colorNameList)
        """
    }

    /// Every palette name paired with its bright counterpart, matching the
    /// grouping `TabColor.hueFamily` already draws. `gray` has no bright
    /// pair, so it stands alone.
    private static let pairedColorNames: [(TabColor, TabColor)] = [
        (.red, .brightRed), (.green, .brightGreen), (.yellow, .brightYellow),
        (.blue, .brightBlue), (.magenta, .brightMagenta), (.cyan, .brightCyan),
        (.neutral, .neutralBright)
    ]

    private static func swatch(_ color: TabColor) -> String {
        "\u{1B}[\(color.ansiCode)m\u{25A0}\u{1B}[0m"
    }

    private static var colorNameList: String {
        let rows = pairedColorNames.map { base, bright -> String in
            let name = base.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)
            return "  \(swatch(base)) \(name)\(swatch(bright)) \(bright.rawValue)"
        }
        return (rows + ["  \(swatch(.gray)) gray"]).joined(separator: "\n")
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

    static func parse(_ arguments: [String]) -> Result<ParsedInvocation, UsageError> {
        guard let first = arguments.first else { return .failure(.noArguments) }

        if let topLevel = parseTopLevel(first, arguments: arguments) {
            return topLevel
        }

        guard let scope = ControlScope(rawValue: first) else {
            return .failure(.unknownScope(first))
        }
        guard arguments.count >= 2 else { return .failure(.missingValue("property")) }
        if arguments.count > 3 { return .failure(.unexpectedArgument(arguments[3])) }
        let property = arguments[1]
        let value = arguments.count >= 3 ? arguments[2] : nil

        switch (scope, property) {
        case (_, "color"):
            return parseColor(scope: scope, value: value)
        case (.tab, "name"):
            return parseName(value)
        case (.surface, "status"):
            return parseStatus(value)
        default:
            return .failure(.unknownProperty(property))
        }
    }

    /// Handles the invocations that stand outside the scope/property/value
    /// grammar. Returns nil when `first` is not one of those keywords, so the
    /// caller falls through to scope parsing.
    private static func parseTopLevel(
        _ first: String, arguments: [String]
    ) -> Result<ParsedInvocation, UsageError>? {
        switch first {
        case "--version", "-v":
            return exactly(1, of: arguments, is: .version)
        case "--help", "-h":
            return exactly(1, of: arguments, is: .help)
        case "info":
            return exactly(1, of: arguments, is: .control(.info))
        case "hook":
            guard arguments.count >= 2 else { return .failure(.missingValue("hook")) }
            return exactly(2, of: arguments, is: .hook(arguments[1]))
        case "tint-strength":
            guard arguments.count >= 2 else { return .failure(.missingValue("tint-strength")) }
            guard arguments.count <= 2 else { return .failure(.unexpectedArgument(arguments[2])) }
            return parseTintStrength(arguments[1])
        default:
            return nil
        }
    }

    private static func parseTintStrength(_ value: String) -> Result<ParsedInvocation, UsageError> {
        if value == "--reset" {
            return .success(.control(.setTintStrength(SurfaceTintStrength.default)))
        }
        guard let strength = Double(value), SurfaceTintStrength.range.contains(strength) else {
            return .failure(.badTintStrength(value))
        }
        return .success(.control(.setTintStrength(strength)))
    }

    /// Every invocation has a fixed arity. An argument past it means the caller
    /// left a value unquoted, and parsing the prefix would silently apply a
    /// different command than the one they typed.
    private static func exactly(
        _ count: Int, of arguments: [String], is invocation: ParsedInvocation
    ) -> Result<ParsedInvocation, UsageError> {
        arguments.count > count
            ? .failure(.unexpectedArgument(arguments[count]))
            : .success(invocation)
    }

    private static func parseColor(
        scope: ControlScope, value: String?
    ) -> Result<ParsedInvocation, UsageError> {
        guard let value else { return .success(.showColor(scope)) }
        if value == "--reset" { return .success(.control(.clearColor(scope: scope))) }
        return parseTint(value).map { .control(.setColor(scope: scope, tint: $0)) }
    }

    private static func parseName(_ value: String?) -> Result<ParsedInvocation, UsageError> {
        guard let value else { return .failure(.missingValue("name")) }
        if value == "--reset" { return .success(.control(.clearName)) }
        return .success(.control(.setName(value)))
    }

    private static func parseStatus(_ value: String?) -> Result<ParsedInvocation, UsageError> {
        guard let value else { return .failure(.missingValue("status")) }
        switch value {
        case "working": return .success(.control(.setStatus(.working)))
        case "waiting": return .success(.control(.setStatus(.waiting)))
        case "idle":    return .success(.control(.setStatus(.idle)))
        case "clear":   return .success(.control(.setStatus(nil)))
        default:        return .failure(.unknownStatus(value))
        }
    }

    private static func parseTint(_ spec: String) -> Result<PaneTint, UsageError> {
        let parts = spec.components(separatedBy: ",")
        guard parts.count <= PaneTint.maxStops else { return .failure(.tooManyStops) }

        var stops: [TintStop] = []
        for part in parts {
            guard let stop = TintStop.parse(part) else { return .failure(.badColor(part)) }
            stops.append(stop)
        }
        guard !stops.isEmpty else { return .failure(.badColor(spec)) }
        return .success(PaneTint(stops: stops))
    }
}
