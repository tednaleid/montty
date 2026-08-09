// ABOUTME: Verifies the montty CLI grammar translates argv into
// ABOUTME: ControlCommand values, or a specific UsageError for bad input.

import Foundation
import Testing

@Suite struct ControlArgsTests {
    private func command(_ args: [String]) -> ControlCommand? {
        guard case .success(.control(let command)) = ControlArgs.parse(args) else { return nil }
        return command
    }

    private func failure(_ args: [String]) -> ControlArgs.UsageError? {
        guard case .failure(let error) = ControlArgs.parse(args) else { return nil }
        return error
    }

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

    @Test func parsesResetForEachScope() {
        #expect(command(["surface", "color", "--reset"]) == .clearColor(scope: .surface))
        #expect(command(["tab", "color", "--reset"]) == .clearColor(scope: .tab))
        #expect(command(["repo", "color", "--reset"]) == .clearColor(scope: .repo))
    }

    @Test func parsesNameAndReset() {
        #expect(command(["tab", "name", "MR !123 fix auth"]) == .setName("MR !123 fix auth"))
        #expect(command(["tab", "name", "--reset"]) == .clearName)
    }

    @Test func parsesStatus() {
        #expect(command(["surface", "status", "working"]) == .setStatus(.working))
        #expect(command(["surface", "status", "waiting"]) == .setStatus(.waiting))
        #expect(command(["surface", "status", "idle"]) == .setStatus(.idle))
        #expect(command(["surface", "status", "clear"]) == .setStatus(nil))
    }

    @Test func parsesInfoAndVersion() {
        #expect(command(["info"]) == .info)
        guard case .success(.version) = ControlArgs.parse(["--version"]) else {
            Issue.record("expected version")
            return
        }
    }

    @Test func parsesHook() {
        guard case .success(.hook(let event)) = ControlArgs.parse(["hook", "pre-tool-use"]) else {
            Issue.record("expected hook")
            return
        }
        #expect(event == "pre-tool-use")
    }

    @Test func rejectsBadColorSpecs() {
        #expect(failure(["tab", "color", "chartreuse"]) == .badColor("chartreuse"))
        #expect(failure(["tab", "color", "#fff"]) == .badColor("#fff"))
        #expect(failure(["tab", "color", "red,green,blue,cyan"]) == .tooManyStops)
        #expect(failure(["tab", "color", ""]) == .badColor(""))
    }

    @Test func rejectsUnknownScopesVerbsAndStatuses() {
        #expect(failure(["window", "color", "red"]) == .unknownScope("window"))
        #expect(failure(["tab", "opacity", "0.5"]) == .unknownProperty("opacity"))
        #expect(failure(["surface", "status", "thinking"]) == .unknownStatus("thinking"))
        #expect(failure(["surface", "name", "x"]) == .unknownProperty("name"))
        #expect(failure(["tab", "status", "idle"]) == .unknownProperty("status"))
        #expect(failure([]) == .noArguments)
    }

    @Test func rejectsAMissingValue() {
        #expect(failure(["tab", "color"]) == .missingValue("color"))
        #expect(failure(["tab", "name"]) == .missingValue("name"))
    }

    @Test func rejectsScopeWithNoProperty() {
        #expect(failure(["tab"]) == .missingValue("property"))
        #expect(failure(["surface"]) == .missingValue("property"))
        #expect(failure(["repo"]) == .missingValue("property"))
    }

    @Test func aMistypedVerbIsAUsageErrorRatherThanALaunch() {
        #expect(failure(["nope"]) == .unknownScope("nope"))
        #expect(failure(["tabb", "color", "green"]) == .unknownScope("tabb"))
        #expect(failure(["tab-color", "green"]) == .unknownScope("tab-color"))
    }

    @Test func parsesHelpFlags() {
        guard case .success(.help) = ControlArgs.parse(["--help"]),
              case .success(.help) = ControlArgs.parse(["-h"]) else {
            Issue.record("expected help")
            return
        }
    }

    @Test func rejectsArgumentsBeyondAnInvocationsArity() {
        #expect(failure(["tab", "name", "MR", "123", "fix", "auth"]) == .unexpectedArgument("123"))
        #expect(failure(["tab", "name", "--reset", "extra"]) == .unexpectedArgument("extra"))
        #expect(failure(["surface", "color", "green", "ignored"]) == .unexpectedArgument("ignored"))
        #expect(failure(["info", "extra"]) == .unexpectedArgument("extra"))
        #expect(failure(["--version", "extra"]) == .unexpectedArgument("extra"))
        #expect(failure(["--help", "extra"]) == .unexpectedArgument("extra"))
        #expect(failure(["hook", "stop", "extra"]) == .unexpectedArgument("extra"))
    }

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
