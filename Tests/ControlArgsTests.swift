// ABOUTME: Verifies the montty CLI grammar translates argv into ControlCommand
// ABOUTME: values and setting reads, and answers bad input and --help with text.

import Foundation
import Testing

@Suite struct ControlArgsTests {
    private func command(_ args: [String]) -> ControlCommand? {
        guard case .success(.control(let command)) = ControlArgs.parse(args) else { return nil }
        return command
    }

    private func read(_ args: [String]) -> SettingRead? {
        guard case .success(.read(let read)) = ControlArgs.parse(args) else { return nil }
        return read
    }

    private func exit(_ args: [String]) -> ControlArgs.ParseExit? {
        guard case .failure(let exit) = ControlArgs.parse(args) else { return nil }
        return exit
    }

    private func isUsageError(_ args: [String]) -> Bool {
        exit(args)?.exitCode == ExitCode.usage.rawValue
    }

    private func help(_ args: [String]) -> String? {
        guard let exit = exit(args), exit.exitCode == ExitCode.ok.rawValue else { return nil }
        return exit.message
    }

    // MARK: - Color

    @Test func parsesSingleColorForEachScope() {
        #expect(command(["surface", "color", "#1a7f37"]) == .setColor(
            scope: .surface, tint: PaneTint(stops: [.hex(RGB(r: 0x1A, g: 0x7F, b: 0x37))])
        ))
        #expect(command(["tab", "color", "green"]) == .setColor(
            scope: .tab, tint: PaneTint(stops: [.named(.green)])
        ))
        #expect(command(["repo", "color", "cyan"]) == .setColor(
            scope: .repo, tint: PaneTint(stops: [.named(.cyan)])
        ))
    }

    @Test func parsesTwoAndThreeStopGradients() {
        #expect(command(["surface", "color", "neutralBright,green"]) == .setColor(
            scope: .surface,
            tint: PaneTint(stops: [.named(.neutralBright), .named(.green)])
        ))
        #expect(command(["tab", "color", "blue,brightMagenta,cyan"]) == .setColor(
            scope: .tab,
            tint: PaneTint(stops: [.named(.blue), .named(.brightMagenta), .named(.cyan)])
        ))
    }

    @Test func parsesColorResetForEachScope() {
        #expect(command(["surface", "color", "--reset"]) == .clearColor(scope: .surface))
        #expect(command(["tab", "color", "--reset"]) == .clearColor(scope: .tab))
        #expect(command(["repo", "color", "--reset"]) == .clearColor(scope: .repo))
    }

    @Test(arguments: [
        ["tab", "color", "chartreuse"], ["tab", "color", "#fff"],
        ["tab", "color", "red,green,blue,cyan"], ["tab", "color", ""],
        ["app", "color", "green"]
    ])
    func rejectsABadColor(args: [String]) {
        #expect(isUsageError(args))
    }

    // MARK: - Name, status, resume command

    @Test func parsesNameAndReset() {
        #expect(command(["tab", "name", "MR !123 fix auth"]) == .setName("MR !123 fix auth"))
        #expect(command(["tab", "name", "--reset"]) == .clearName)
    }

    @Test func parsesStatus() {
        #expect(command(["surface", "status", "working"]) == .setStatus(.working))
        #expect(command(["surface", "status", "waiting"]) == .setStatus(.waiting))
        #expect(command(["surface", "status", "idle"]) == .setStatus(.idle))
        #expect(command(["surface", "status", "clear"]) == .setStatus(nil))
        #expect(command(["surface", "status", "--reset"]) == .setStatus(nil))
    }

    @Test func parsesResumeCommandAndReset() {
        #expect(
            command(["surface", "resume-command", "nvim -S 'my session.vim'"])
                == .setResumeCommand("nvim -S 'my session.vim'")
        )
        #expect(command(["surface", "resume-command", "--reset"]) == .setResumeCommand(nil))
    }

    // MARK: - Minimap and strengths

    @Test func parsesTheAppMinimapVisibility() {
        #expect(command(["app", "minimap", "always"]) == .setMinimapVisibility(.always))
        #expect(command(["app", "minimap", "never"]) == .setMinimapVisibility(.never))
        #expect(command(["app", "minimap", "status,split"])
            == .setMinimapVisibility(.when([.split, .status])))
        #expect(command(["app", "minimap", "--reset"]) == .setMinimapVisibility(.always))
    }

    @Test func parsesTheTabMinimapVisibility() {
        #expect(command(["tab", "minimap", "split"])
            == .setTabMinimapVisibility(.when([.split])))
        #expect(command(["tab", "minimap", "--reset"]) == .setTabMinimapVisibility(nil))
    }

    @Test(arguments: [
        ["app", "minimap", "sometimes"], ["app", "minimap", "always,split"],
        ["tab", "minimap", ""], ["app", "minimap", "split", "status"]
    ])
    func rejectsABadMinimapVisibility(args: [String]) {
        #expect(isUsageError(args))
    }

    @Test func parsesTheMinimapHeightWithinItsRange() {
        #expect(command(["app", "minimap-height", "40"]) == .setMinimapHeight(scope: .app, value: 40))
        #expect(command(["app", "minimap-height", "200"]) == .setMinimapHeight(scope: .app, value: 200))
        #expect(command(["app", "minimap-height", "--reset"])
            == .setMinimapHeight(scope: .app, value: nil))
        #expect(isUsageError(["app", "minimap-height", "39"]))
        #expect(isUsageError(["app", "minimap-height", "201"]))
        #expect(isUsageError(["app", "minimap-height", "tall"]))
    }

    @Test func parsesTheSurfaceTintStrengthWithinItsRange() {
        #expect(command(["app", "surface-tint-strength", "0.2"]) == .setStrength(.surfaceTint, scope: .app, value: 0.2))
        #expect(command(["app", "surface-tint-strength", "0"]) == .setStrength(.surfaceTint, scope: .app, value: 0))
        #expect(command(["app", "surface-tint-strength", "0.5"]) == .setStrength(.surfaceTint, scope: .app, value: 0.5))
        #expect(command(["app", "surface-tint-strength", "--reset"])
            == .setStrength(.surfaceTint, scope: .app, value: nil))
    }

    @Test(arguments: ["0.51", "1", "-0.1", "nope", "nan"])
    func rejectsASurfaceTintStrengthOutsideItsRange(value: String) {
        #expect(isUsageError(["app", "surface-tint-strength", value]))
    }

    @Test func parsesTheTabTintStrengthWithinItsRange() {
        #expect(command(["app", "tab-tint-strength", "0"]) == .setStrength(.tabTint, scope: .app, value: 0))
        #expect(command(["app", "tab-tint-strength", "0.3"]) == .setStrength(.tabTint, scope: .app, value: 0.3))
        #expect(command(["app", "tab-tint-strength", "--reset"])
            == .setStrength(.tabTint, scope: .app, value: nil))
        #expect(isUsageError(["app", "tab-tint-strength", "-0.1"]))
        #expect(isUsageError(["app", "tab-tint-strength", "0.31"]))
        #expect(isUsageError(["app", "tab-tint-strength", "strong"]))
    }

    @Test(arguments: [SettingScope.surface, .tab, .repo, .app])
    func aStrengthIsSetAndResetAtEveryScope(scope: SettingScope) {
        let name = scope.rawValue
        #expect(command([name, "surface-tint-strength", "0.2"])
            == .setStrength(.surfaceTint, scope: scope, value: 0.2))
        #expect(command([name, "surface-tint-strength", "--reset"])
            == .setStrength(.surfaceTint, scope: scope, value: nil))
        #expect(command([name, "tab-tint-strength", "0.2"])
            == .setStrength(.tabTint, scope: scope, value: 0.2))
        #expect(read([name, "tab-tint-strength"])
            == SettingRead(setting: .tabTintStrength, scope: scope))
    }

    @Test func theMinimapHeightIsSetAndResetForATab() {
        #expect(command(["tab", "minimap-height", "60"]) == .setMinimapHeight(scope: .tab, value: 60))
        #expect(command(["tab", "minimap-height", "--reset"])
            == .setMinimapHeight(scope: .tab, value: nil))
        #expect(read(["tab", "minimap-height"]) == SettingRead(setting: .minimapHeight, scope: .tab))
    }

    @Test func aNameIsSetAndResetForASurface() {
        #expect(command(["surface", "name", "logs"]) == .setSurfaceName("logs"))
        #expect(command(["surface", "name", "--reset"]) == .setSurfaceName(nil))
        #expect(read(["surface", "name"]) == SettingRead(setting: .name, scope: .surface))
    }

    // MARK: - The read form

    @Test func aSettingWithNoValueReadsItBack() {
        #expect(read(["surface", "color"]) == SettingRead(setting: .color, scope: .surface))
        #expect(read(["tab", "color"]) == SettingRead(setting: .color, scope: .tab))
        #expect(read(["repo", "color"]) == SettingRead(setting: .color, scope: .repo))
        #expect(read(["tab", "name"]) == SettingRead(setting: .name, scope: .tab))
        #expect(read(["surface", "status"]) == SettingRead(setting: .status, scope: .surface))
        #expect(read(["surface", "resume-command"])
            == SettingRead(setting: .resumeCommand, scope: .surface))
        #expect(read(["tab", "minimap"]) == SettingRead(setting: .minimap, scope: .tab))
        #expect(read(["app", "minimap"]) == SettingRead(setting: .minimap, scope: .app))
        #expect(read(["app", "minimap-height"])
            == SettingRead(setting: .minimapHeight, scope: .app))
        #expect(read(["app", "surface-tint-strength"])
            == SettingRead(setting: .surfaceTintStrength, scope: .app))
        #expect(read(["app", "tab-tint-strength"])
            == SettingRead(setting: .tabTintStrength, scope: .app))
    }

    @Test func aValueAndResetTogetherAreAUsageError() {
        #expect(isUsageError(["tab", "name", "x", "--reset"]))
        #expect(isUsageError(["app", "minimap", "never", "--reset"]))
    }

    // MARK: - Scopes

    @Test(arguments: [
        ["surface", "minimap", "never"], ["repo", "minimap", "never"],
        ["repo", "name", "x"], ["app", "name", "x"], ["tab", "status", "idle"],
        ["tab", "resume-command", "nvim"], ["surface", "minimap-height", "60"],
        ["repo", "minimap-height", "60"]
    ])
    func aSettingAtAScopeThatDoesNotAcceptItIsAUsageError(args: [String]) {
        #expect(isUsageError(args))
    }

    @Test(arguments: [
        ["tint-strength", "0.2"], ["minimap", "never"],
        ["minimap-height", "60"], ["tab-tint-strength", "0.2"]
    ])
    func aSettingWithNoScopeIsAUsageError(args: [String]) {
        #expect(isUsageError(args))
    }

    @Test(arguments: [
        ["window", "color", "red"], ["tab", "opacity", "0.5"],
        ["surface", "status", "thinking"], ["nope"],
        ["tabb", "color", "green"], ["tab-color", "green"]
    ])
    func rejectsUnknownScopesSettingsAndStatuses(args: [String]) {
        #expect(isUsageError(args))
    }

    @Test(arguments: [
        ["tab", "name", "MR", "123", "fix", "auth"], ["tab", "name", "--reset", "extra"],
        ["surface", "color", "green", "ignored"], ["info", "extra"],
        ["--version", "extra"], ["app", "surface-tint-strength", "0.2", "extra"],
        ["surface", "resume-command", "nvim", "-S"]
    ])
    func rejectsArgumentsBeyondACommandsArity(args: [String]) {
        #expect(isUsageError(args))
    }

    // MARK: - Verbs

    @Test func parsesInfoAndVersion() {
        #expect(command(["info"]) == .info)
        #expect(ControlArgs.parse(["--version"]) == .success(.version))
        #expect(ControlArgs.parse(["-v"]) == .success(.version))
    }

    @Test func parsesHook() {
        #expect(
            ControlArgs.parse(["hook", "pre-tool-use"])
                == .success(.hook(event: "pre-tool-use", hooksVersion: nil))
        )
        #expect(
            ControlArgs.parse(["hook", "session-start", "--hooks-version", "2"])
                == .success(.hook(event: "session-start", hooksVersion: 2))
        )
        #expect(isUsageError(["hook"]))
    }

    /// Hook entries are written by whichever montty installed them, which can
    /// be newer than the one running, so `hook` skips arguments it does not
    /// know. A hook must never print, so `--help` is one of those.
    @Test func hookIgnoresArgumentsItDoesNotKnow() {
        #expect(ControlArgs.parse(["hook", "stop", "extra"]) == .success(.hook(event: "stop", hooksVersion: nil)))
        #expect(
            ControlArgs.parse(["hook", "stop", "--future", "x", "--hooks-version", "3"])
                == .success(.hook(event: "stop", hooksVersion: 3))
        )
        #expect(
            ControlArgs.parse(["hook", "stop", "--hooks-version", "two"])
                == .success(.hook(event: "stop", hooksVersion: nil))
        )
        #expect(ControlArgs.parse(["hook", "stop", "--help"]) == .success(.hook(event: "stop", hooksVersion: nil)))
    }

    @Test func parsesInstallAndUninstallHooks() {
        #expect(ControlArgs.parse(["install-hooks", "claude"]) == .success(.installHooks(.claude)))
        #expect(ControlArgs.parse(["uninstall-hooks", "claude"]) == .success(.uninstallHooks(.claude)))
    }

    @Test func installHooksNeedsAKnownAgent() {
        #expect(isUsageError(["install-hooks"]))
        #expect(isUsageError(["uninstall-hooks"]))
        #expect(isUsageError(["install-hooks", "codex"]))
        #expect(isUsageError(["install-hooks", "claude", "extra"]))
    }

    // MARK: - Help and usage errors

    @Test(arguments: [["--help"], ["-h"]])
    func theOverviewListsEveryScopeAndVerbWithoutThePalette(args: [String]) throws {
        let text = try #require(help(args))
        for word in ["surface", "tab", "repo", "app", "info", "hook", "install-hooks", "uninstall-hooks"] {
            #expect(text.contains(word), "missing \(word)")
        }
        #expect(!text.contains("brightMagenta"))
    }

    @Test func aScopesHelpListsTheSettingsItAccepts() throws {
        let text = try #require(help(["tab", "--help"]))
        for setting in ["color", "name", "minimap"] {
            #expect(text.contains(setting), "missing \(setting)")
        }
        #expect(!text.contains("resume-command"))
        #expect(!text.contains("brightMagenta"))
    }

    @Test func aScopeWithNoSettingPrintsThatScopesHelp() {
        #expect(help(["tab"]) == help(["tab", "--help"]))
        #expect(help(["app"]) == help(["app", "--help"]))
    }

    @Test func colorHelpListsEveryPaletteNameWithItsAnsiSwatch() throws {
        let text = try #require(help(["tab", "color", "--help"]))
        for color in TabColor.allCases {
            #expect(text.contains(color.rawValue))
            #expect(text.contains("\u{1B}[\(color.ansiCode)m"))
        }
    }

    @Test func aSettingsHelpGivesItsRangeAndDefault() throws {
        let text = try #require(help(["app", "surface-tint-strength", "--help"]))
        #expect(text.contains("0.5"))
        #expect(text.contains("0.12"))
        #expect(!text.contains("brightMagenta"))
    }

    @Test func aUsageErrorNamesTheCommandItRecognisedAndNotThePalette() throws {
        let failure = try #require(exit(["app", "surface-tint-strength", "0.9"]))
        #expect(failure.exitCode == ExitCode.usage.rawValue)
        #expect(failure.message.contains("montty app surface-tint-strength"))
        #expect(failure.message.contains("0.9"))
        #expect(!failure.message.contains("brightMagenta"))
    }

    @Test func aBadColorSaysWhichStopWasWrong() throws {
        let failure = try #require(exit(["tab", "color", "red,chartreuse"]))
        #expect(failure.message.contains("chartreuse"))
        #expect(failure.message.contains("montty tab color"))
    }

    // MARK: - Launch or command

    @Test func classifiesLaunchArgumentsVersusCLIInvocations() {
        let cases: [(arguments: [String], isCLI: Bool)] = [
            ([], false),
            (["-psn_0_12345"], false),
            (["-NSDocumentRevisionsDebugMode", "YES"], false),
            (["-AppleLanguages", "(en)"], false),
            (["-NSTreatUnknownArgumentsAsOpen", "NO"], false),
            (["--frobnicate"], false),
            (["-v"], true),
            (["--version"], true),
            (["-h"], true),
            (["--help"], true),
            (["info"], true),
            (["hook", "stop"], true),
            (["surface", "color", "green"], true),
            (["tabb", "color", "green"], true),
            (["tab-color", "green"], true),
            (["nope"], true)
        ]
        for testCase in cases {
            #expect(
                ControlArgs.isInvocation(testCase.arguments) == testCase.isCLI,
                "arguments: \(testCase.arguments)"
            )
        }
    }
}
