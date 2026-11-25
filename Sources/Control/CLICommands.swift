// ABOUTME: Declares montty's command-line grammar: each scope, the settings it
// ABOUTME: accepts, and the verbs, as swift-argument-parser commands.

import ArgumentParser
import Foundation

/// One setting of the grammar: its name, its help, and how the text typed
/// for it becomes a command. A setting is declared once and listed under
/// each scope that accepts it.
protocol SettingDefinition {
    static var name: SettingName { get }
    static var summary: String { get }
    static var discussion: String { get }
    /// The placeholder the usage line shows for the value.
    static var valueName: String { get }
    static var valueHelp: String { get }
    /// Throws a `ValidationError` for text that is not a value of the setting.
    static func set(_ text: String, at scope: SettingScope) throws -> ControlCommand
    static func reset(at scope: SettingScope) -> ControlCommand
}

extension SettingDefinition {
    static var discussion: String { "" }

    /// A number within `range`, or a usage error naming the range.
    static func number(_ text: String, in range: ClosedRange<Double>) throws -> Double {
        guard let value = Double(text), range.contains(value) else {
            throw ValidationError(
                "not a number between \(range.lowerBound) and \(range.upperBound): \"\(text)\""
            )
        }
        return value
    }
}

/// A scope as a type, so one setting declaration serves every scope.
protocol ScopeMarker {
    static var scope: SettingScope { get }
}

/// A parsed command that montty runs, as opposed to one that prints help.
protocol InvocationCommand {
    func invocation() throws -> ParsedInvocation
}

enum CLI {
    /// Parses everything but the version flags and `hook`. Help that was
    /// asked for and usage errors both come back as a `ParseExit`.
    static func parse(_ arguments: [String]) -> Result<ParsedInvocation, ControlArgs.ParseExit> {
        do {
            var command = try Root.parseAsRoot(arguments)
            if let runnable = command as? InvocationCommand {
                return .success(try runnable.invocation())
            }
            // A scope with no setting, or a request for help: running it
            // throws the help text.
            try command.run()
            return .failure(ControlArgs.ParseExit(message: Root.helpMessage(), exitCode: 0))
        } catch {
            return .failure(ControlArgs.ParseExit(
                message: Root.fullMessage(for: error),
                exitCode: Root.exitCode(for: error).rawValue
            ))
        }
    }

    enum AtSurface: ScopeMarker { static let scope = SettingScope.surface }
    enum AtTab: ScopeMarker { static let scope = SettingScope.tab }
    enum AtRepo: ScopeMarker { static let scope = SettingScope.repo }
    enum AtApp: ScopeMarker { static let scope = SettingScope.app }

    /// `montty <scope> <setting> [<value> | --reset]`.
    struct Setting<Definition: SettingDefinition, Scope: ScopeMarker>: ParsableCommand, InvocationCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: Definition.name.rawValue,
                abstract: Definition.summary,
                discussion: Definition.discussion
            )
        }

        @Argument(help: ArgumentHelp(
            "\(Definition.valueHelp) Omit it to print the current value.",
            valueName: Definition.valueName
        ))
        var value: String?

        @Flag(help: ArgumentHelp(
            Scope.scope == .app
                ? "Return the setting to its default."
                : "Remove the value set at this scope."
        ))
        var reset = false

        func validate() throws {
            _ = try invocation()
        }

        func invocation() throws -> ParsedInvocation {
            switch (value, reset) {
            case (.some, true):
                throw ValidationError("give a value or --reset, not both")
            case (nil, true):
                return .control(Definition.reset(at: Scope.scope))
            case (nil, false):
                return .read(SettingRead(setting: Definition.name, scope: Scope.scope))
            case (let value?, false):
                return .control(try Definition.set(value, at: Scope.scope))
            }
        }
    }

    struct Root: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "montty",
            abstract: "Style the montty surface, tab, repo, or app this command runs in.",
            discussion: """
            A setting is named after a scope: montty <scope> <setting> <value>.
            Give no value to print the current one, or --reset to clear it.
            """,
            subcommands: [
                SurfaceScope.self, TabScope.self, RepoScope.self, AppScope.self,
                Info.self, Hook.self, InstallHooks.self, UninstallHooks.self, Launch.self
            ]
        )
    }

    /// `montty tab new [--dir <path>] [--name <text>] [--focus] [-- <command> ...]`.
    struct TabNew: ParsableCommand, InvocationCommand {
        static let configuration = CommandConfiguration(
            commandName: "new",
            abstract: "Open a tab in this window, optionally running a command in it.",
            discussion: """
            The tab opens after this window's other tabs and stays in the
            background unless --focus is given. Everything after -- is a
            command for the new shell to run. Its arguments arrive exactly as
            given, whatever they contain:

              montty tab new --name review -- claude "look at the failing tests"
            """
        )

        @Option(
            name: .customLong("dir"),
            help: "Where the new shell starts. Defaults to this surface's directory."
        )
        var directory: String?

        @Option(help: "The new tab's name.")
        var name: String?

        @Flag(help: "Make the new tab the active one.")
        var focus = false

        @Argument(parsing: .postTerminator, help: "A command to run in the new tab, after --.")
        var command: [String] = []

        func validate() throws {
            _ = try invocation()
        }

        func invocation() throws -> ParsedInvocation {
            guard NewTab.isValidCommand(command) else {
                throw ValidationError(
                    "the command needs a program to run, at most "
                        + "\(NewTab.maxCommandCharacters) characters, and no NUL bytes"
                )
            }
            if let name, name.count > ControlWire.maxNameCharacters {
                throw ValidationError("a name is at most \(ControlWire.maxNameCharacters) characters")
            }
            return .control(.newTab(
                NewTab(directory: directory, name: name, command: command, focus: focus)
            ))
        }
    }

    /// Typed by montty in a tab opened with a command, so it is left out of
    /// help.
    struct Launch: ParsableCommand, InvocationCommand {
        static let configuration = CommandConfiguration(
            commandName: "launch",
            abstract: "Run the command montty kept for this surface.",
            shouldDisplay: false
        )

        func invocation() -> ParsedInvocation { .control(.takeLaunch) }
    }

    struct SurfaceScope: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: SettingScope.surface.rawValue,
            abstract: "Settings for the surface this command runs in.",
            subcommands: [
                Setting<ColorSetting, AtSurface>.self,
                Setting<NameSetting, AtSurface>.self,
                Setting<StatusSetting, AtSurface>.self,
                Setting<ResumeCommandSetting, AtSurface>.self,
                Setting<SurfaceTintStrengthSetting, AtSurface>.self,
                Setting<TabTintStrengthSetting, AtSurface>.self
            ]
        )
    }

    struct TabScope: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: SettingScope.tab.rawValue,
            abstract: "Settings for the tab this command runs in, and opening a new one.",
            subcommands: [
                TabNew.self,
                Setting<ColorSetting, AtTab>.self,
                Setting<NameSetting, AtTab>.self,
                Setting<SurfaceTintStrengthSetting, AtTab>.self,
                Setting<TabTintStrengthSetting, AtTab>.self,
                Setting<MinimapSetting, AtTab>.self,
                Setting<MinimapHeightSetting, AtTab>.self
            ]
        )
    }

    struct RepoScope: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: SettingScope.repo.rawValue,
            abstract: "Settings for the repo or worktree this surface is in.",
            subcommands: [
                Setting<ColorSetting, AtRepo>.self,
                Setting<SurfaceTintStrengthSetting, AtRepo>.self,
                Setting<TabTintStrengthSetting, AtRepo>.self
            ]
        )
    }

    struct AppScope: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: SettingScope.app.rawValue,
            abstract: "Settings for the whole app, across all windows.",
            subcommands: [
                Setting<SurfaceTintStrengthSetting, AtApp>.self,
                Setting<TabTintStrengthSetting, AtApp>.self,
                Setting<MinimapSetting, AtApp>.self,
                Setting<MinimapHeightSetting, AtApp>.self
            ]
        )
    }

    struct Info: ParsableCommand, InvocationCommand {
        static let configuration = CommandConfiguration(
            commandName: "info",
            abstract: "Print this surface's state as JSON."
        )

        func invocation() -> ParsedInvocation { .control(.info) }
    }

    /// Listed so help names it. `montty hook` itself never reaches the
    /// library: `ControlArgs.parse` answers it first.
    struct Hook: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "hook",
            abstract: "Report an agent's hook event. Run by the installed hooks."
        )

        @Argument(help: "The event name.")
        var event: String
    }

    struct InstallHooks: ParsableCommand, InvocationCommand {
        static let configuration = CommandConfiguration(
            commandName: "install-hooks",
            abstract: "Add montty's hooks to an agent's settings."
        )

        @Argument(help: "The agent: \(HookAgent.allCases.map(\.rawValue).joined(separator: ", ")).")
        var agent: HookAgent

        func invocation() -> ParsedInvocation { .installHooks(agent) }
    }

    struct UninstallHooks: ParsableCommand, InvocationCommand {
        static let configuration = CommandConfiguration(
            commandName: "uninstall-hooks",
            abstract: "Remove montty's hooks from an agent's settings."
        )

        @Argument(help: "The agent: \(HookAgent.allCases.map(\.rawValue).joined(separator: ", ")).")
        var agent: HookAgent

        func invocation() -> ParsedInvocation { .uninstallHooks(agent) }
    }
}

extension HookAgent: ExpressibleByArgument {}

// MARK: - Settings

enum ColorSetting: SettingDefinition {
    static let name = SettingName.color
    static let summary = "The color, as 1 to 3 stops drawn left to right."
    static let valueName = "spec"
    static let valueHelp = "1 to \(PaneTint.maxStops) comma-separated stops."

    static var discussion: String {
        """
        A stop is a palette name (green, brightMagenta, neutralBright) or a
        six-digit hex value with or without a leading #.

        palette names:
        \(paletteList)
        """
    }

    static func set(_ text: String, at scope: SettingScope) throws -> ControlCommand {
        .setColor(scope: try colorScope(scope), tint: try tint(text))
    }

    static func reset(at scope: SettingScope) -> ControlCommand {
        // Color is listed only under scopes that have a color scope.
        .clearColor(scope: ControlScope(rawValue: scope.rawValue) ?? .surface)
    }

    private static func colorScope(_ scope: SettingScope) throws -> ControlScope {
        guard let colorScope = ControlScope(rawValue: scope.rawValue) else {
            throw ValidationError("color has no \(scope.rawValue) scope")
        }
        return colorScope
    }

    private static func tint(_ spec: String) throws -> PaneTint {
        let parts = spec.components(separatedBy: ",")
        guard parts.count <= PaneTint.maxStops else {
            throw ValidationError("at most \(PaneTint.maxStops) comma-separated stops")
        }
        let stops = try parts.map { part -> TintStop in
            guard let stop = TintStop.parse(part) else {
                throw ValidationError("not a color: \"\(part)\" (use a palette name or #rrggbb)")
            }
            return stop
        }
        return PaneTint(stops: stops)
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

    private static var paletteList: String {
        let rows = pairedColorNames.map { base, bright -> String in
            let name = base.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)
            return "  \(swatch(base)) \(name)\(swatch(bright)) \(bright.rawValue)"
        }
        return (rows + ["  \(swatch(.gray)) gray"]).joined(separator: "\n")
    }
}

enum NameSetting: SettingDefinition {
    static let name = SettingName.name
    static let summary = "The name shown for the tab in the sidebar."
    static let valueName = "text"
    static let valueHelp = "The name. Quote it if it contains spaces."

    static let discussion = """
        A tab shows the name of its focused surface when that surface has one,
        then the tab's own name, then a name made from its directory.
        """

    static func set(_ text: String, at scope: SettingScope) -> ControlCommand {
        scope == .surface ? .setSurfaceName(text) : .setName(text)
    }

    static func reset(at scope: SettingScope) -> ControlCommand {
        scope == .surface ? .setSurfaceName(nil) : .clearName
    }
}

enum StatusSetting: SettingDefinition {
    static let name = SettingName.status
    static let summary = "The activity status shown on the surface's minimap rectangle."
    static let valueName = "state"
    static let valueHelp = "working, waiting, idle, or clear."

    static func set(_ text: String, at scope: SettingScope) throws -> ControlCommand {
        switch text {
        case "working": return .setStatus(.working)
        case "waiting": return .setStatus(.waiting)
        case "idle": return .setStatus(.idle)
        case "clear": return .setStatus(nil)
        default: throw ValidationError("unknown status \"\(text)\"")
        }
    }

    static func reset(at scope: SettingScope) -> ControlCommand { .setStatus(nil) }
}

enum ResumeCommandSetting: SettingDefinition {
    static let name = SettingName.resumeCommand
    static let summary = "The command typed at the surface's prompt when a relaunch restores it."
    static let valueName = "command"
    static let valueHelp = "The shell command, quoted as one argument."

    static func set(_ text: String, at scope: SettingScope) -> ControlCommand {
        .setResumeCommand(text)
    }

    static func reset(at scope: SettingScope) -> ControlCommand { .setResumeCommand(nil) }
}

enum SurfaceTintStrengthSetting: SettingDefinition {
    static let name = SettingName.surfaceTintStrength
    static let summary = "How strongly a terminal surface is tinted with its color."
    static let valueName = "value"
    static let valueHelp = "A number from \(SurfaceTintStrength.range.lowerBound) to "
        + "\(SurfaceTintStrength.range.upperBound). The default is \(SurfaceTintStrength.default)."

    static let discussion = """
        A surface uses the value set on it, then its tab's, then its repo's,
        then the app's.
        """

    static func set(_ text: String, at scope: SettingScope) throws -> ControlCommand {
        .setStrength(.surfaceTint, scope: scope, value: try number(text, in: SurfaceTintStrength.range))
    }

    static func reset(at scope: SettingScope) -> ControlCommand {
        .setStrength(.surfaceTint, scope: scope, value: nil)
    }
}

enum TabTintStrengthSetting: SettingDefinition {
    static let name = SettingName.tabTintStrength
    static let summary = "How strongly a tab in the sidebar is washed with its color."
    static let valueName = "value"
    static let valueHelp = "A number from \(TabTintStrength.range.lowerBound) to "
        + "\(TabTintStrength.range.upperBound). The default is \(TabTintStrength.default)."

    static let discussion = """
        The value is the strength for a tab that is not active and shows its
        minimap. The active tab is a little stronger, and a tab with its
        minimap hidden is stronger again.

        A tab uses the value set on its focused surface, then its own, then
        that surface's repo's, then the app's.
        """

    static func set(_ text: String, at scope: SettingScope) throws -> ControlCommand {
        .setStrength(.tabTint, scope: scope, value: try number(text, in: TabTintStrength.range))
    }

    static func reset(at scope: SettingScope) -> ControlCommand {
        .setStrength(.tabTint, scope: scope, value: nil)
    }
}

enum MinimapSetting: SettingDefinition {
    static let name = SettingName.minimap
    static let summary = "When a tab in the sidebar shows its minimap."
    static let valueName = "when"
    static let valueHelp = "always, never, or a comma-separated list of split and status."

    static let discussion = """
        split shows the minimap while the tab has more than one surface.
        status shows it while a surface in the tab has an activity status.
        With both, either one shows it. The default is always.
        """

    static func set(_ text: String, at scope: SettingScope) throws -> ControlCommand {
        guard let visibility = MinimapVisibility.parse(text) else {
            throw ValidationError("not always, never, or a list of split and status: \"\(text)\"")
        }
        return scope == .app ? .setMinimapVisibility(visibility) : .setTabMinimapVisibility(visibility)
    }

    static func reset(at scope: SettingScope) -> ControlCommand {
        scope == .app ? .setMinimapVisibility(.always) : .setTabMinimapVisibility(nil)
    }
}

enum MinimapHeightSetting: SettingDefinition {
    static let name = SettingName.minimapHeight
    static let summary = "How tall a shown minimap is, in points."
    static let valueName = "points"
    static let valueHelp = "A number from \(Int(MinimapHeight.range.lowerBound)) to "
        + "\(Int(MinimapHeight.range.upperBound)). The default is \(Int(MinimapHeight.default))."

    static func set(_ text: String, at scope: SettingScope) throws -> ControlCommand {
        .setMinimapHeight(scope: scope, value: try number(text, in: MinimapHeight.range))
    }

    static func reset(at scope: SettingScope) -> ControlCommand {
        .setMinimapHeight(scope: scope, value: nil)
    }
}
