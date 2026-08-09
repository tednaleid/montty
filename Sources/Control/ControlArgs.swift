// ABOUTME: Translates montty's argv into a ControlCommand without touching the
// ABOUTME: environment or the network, so the whole grammar is unit-testable.

import Foundation

enum ParsedInvocation: Equatable {
    case control(ControlCommand)
    /// A Claude Code hook event name, forwarded on the legacy wire format.
    case hook(String)
    case version
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
    }

    static let usage = """
        usage: montty <scope> <property> <value>

          montty surface color <spec>      montty surface color --reset
          montty tab     color <spec>      montty tab     color --reset
          montty repo    color <spec>      montty repo    color --reset
          montty tab     name  <text>      montty tab     name  --reset
          montty surface status <working|waiting|idle|clear>
          montty hook <event>
          montty info
          montty --version                 montty -v

        <spec> is 1 to 3 comma-separated stops. A stop is a palette name
        (green, brightMagenta, neutralBright) or a six-digit hex value with
        or without a leading #.
        """

    /// True when the first argument is one montty itself understands --
    /// a scope, a top-level verb, or a version flag -- rather than something
    /// else entirely: a macOS launch argument, a typo, or nothing at all.
    /// Unrecognized input falls through to the GUI, so a launch flag this
    /// doesn't know about still launches normally.
    static func isInvocation(_ arguments: [String]) -> Bool {
        guard let first = arguments.first else { return false }
        switch first {
        case "--version", "-v", "info", "hook":
            return true
        default:
            return ControlScope(rawValue: first) != nil
        }
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
            return .success(.version)
        case "info":
            return .success(.control(.info))
        case "hook":
            guard arguments.count >= 2 else { return .failure(.missingValue("hook")) }
            return .success(.hook(arguments[1]))
        default:
            return nil
        }
    }

    private static func parseColor(
        scope: ControlScope, value: String?
    ) -> Result<ParsedInvocation, UsageError> {
        guard let value else { return .failure(.missingValue("color")) }
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
