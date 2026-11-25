// ABOUTME: Verifies `montty tab new` end to end up to the socket: the grammar that parses it,
// ABOUTME: the wire format that carries it, and the directory a relative --dir resolves to.

import Foundation
import Testing
@testable import montty_unit

@Suite struct NewTabControlTests {
    private func newTab(_ args: [String]) -> NewTab? {
        guard case .success(.control(.newTab(let spec))) = ControlArgs.parse(["tab", "new"] + args)
        else { return nil }
        return spec
    }

    private func isUsageError(_ args: [String]) -> Bool {
        guard case .failure(let exit) = ControlArgs.parse(["tab", "new"] + args) else { return false }
        return exit.exitCode == ExitCode.usage.rawValue
    }

    // MARK: - Grammar

    @Test func bareTabNewOpensAPlainBackgroundTab() {
        #expect(newTab([]) == NewTab())
        #expect(NewTab().focus == false)
        #expect(NewTab().command.isEmpty)
    }

    @Test func parsesEveryFlagInAnyOrder() {
        let expected = NewTab(
            directory: "work/montty", name: "review", command: ["claude", "fix the build"], focus: true
        )

        #expect(newTab(["--dir", "work/montty", "--name", "review", "--focus",
                        "--", "claude", "fix the build"]) == expected)
        #expect(newTab(["--focus", "--name", "review", "--dir", "work/montty",
                        "--", "claude", "fix the build"]) == expected)
    }

    /// Everything after `--` belongs to the command, so its own flags and a
    /// second `--` reach it untouched.
    @Test func argumentsAfterTheTerminatorAreTheCommandWhateverTheyLookLike() {
        #expect(newTab(["--", "claude", "--focus", "--", "-n"])?.command
            == ["claude", "--focus", "--", "-n"])
        #expect(newTab(["--", "claude", "--focus"])?.focus == false)
    }

    @Test func anArgumentKeepsNewlinesQuotesAndDollars() {
        let prompt = "line one\nline \"two\" $(whoami) 'three'"

        #expect(newTab(["--", "claude", prompt])?.command == ["claude", prompt])
    }

    @Test func aFlagWithNoValueIsAUsageError() {
        #expect(isUsageError(["--dir"]))
        #expect(isUsageError(["--name"]))
    }

    @Test func anUnknownFlagIsRefused() {
        #expect(isUsageError(["--bogus"]))
    }

    /// A command without `--` in front could be a mistyped flag value, so it
    /// is refused rather than run.
    @Test func aCommandWithoutTheTerminatorIsRefused() {
        #expect(isUsageError(["claude", "fix the build"]))
    }

    @Test func aCommandWithNoProgramIsRefused() {
        #expect(isUsageError(["--", "", "argument"]))
    }

    @Test func helpIsSpecificToTabNew() {
        guard case .failure(let exit) = ControlArgs.parse(["tab", "new", "--help"]) else {
            Issue.record("help did not exit"); return
        }
        #expect(exit.exitCode == 0)
        #expect(exit.message.contains("--dir"))
        #expect(!exit.message.contains("palette"))
    }

    @Test func launchParsesAndIsLeftOutOfHelp() {
        #expect(ControlArgs.parse(["launch"]) == .success(.control(.takeLaunch)))
        guard case .failure(let exit) = ControlArgs.parse(["--help"]) else {
            Issue.record("help did not exit"); return
        }
        #expect(!exit.message.contains("launch"))
    }

    // MARK: - Wire

    private func roundTrip(_ spec: NewTab) throws -> NewTab? {
        let data = try ControlRequest(surface: "M1", command: .newTab(spec)).encoded()
        guard case .newTab(let decoded) = try ControlRequest.decode(data).command else { return nil }
        return decoded
    }

    @Test func aFullRequestRoundTrips() throws {
        let spec = NewTab(
            directory: "/Users/dev/work/montty", name: "review",
            command: ["claude", "line one\nline \"two\" $(whoami)"], focus: true
        )

        #expect(try roundTrip(spec) == spec)
    }

    @Test func aBareRequestRoundTrips() throws {
        #expect(try roundTrip(NewTab()) == NewTab())
    }

    @Test func anEmptyArgumentSurvivesTheWire() throws {
        #expect(try roundTrip(NewTab(command: ["claude", ""]))?.command == ["claude", ""])
    }

    @Test func aLaunchRequestRoundTrips() throws {
        let data = try ControlRequest(surface: "M1", command: .takeLaunch).encoded()

        #expect(try ControlRequest.decode(data).command == .takeLaunch)
    }

    @Test func aLaunchReplyCarriesTheCommand() throws {
        let data = try ControlResponse.launch(["claude", "a\nb"]).encoded()
        let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(reply?["ok"] as? Bool == true)
        #expect(reply?["command"] as? [String] == ["claude", "a\nb"])
    }

    @Test func aMissingFocusKeyMeansBackground() throws {
        let json = Data(#"{"v":1,"cmd":"new-tab","surface":"M1"}"#.utf8)

        guard case .newTab(let spec) = try ControlRequest.decode(json).command else {
            Issue.record("not a new-tab command"); return
        }
        #expect(spec == NewTab())
    }

    @Test func aRelativeDirectoryIsRefused() {
        let json = Data(#"{"v":1,"cmd":"new-tab","surface":"M1","dir":"work/montty"}"#.utf8)

        #expect(throws: ControlRequest.DecodeFailure.invalidNewTab) {
            try ControlRequest.decode(json)
        }
    }

    @Test func aCommandWithANulByteIsRefused() {
        let json = Data(#"{"v":1,"cmd":"new-tab","surface":"M1","command":["claude","a\u0000b"]}"#.utf8)

        #expect(throws: ControlRequest.DecodeFailure.invalidNewTab) {
            try ControlRequest.decode(json)
        }
    }

    @Test func aCommandPastTheLimitIsRefused() throws {
        let long = String(repeating: "x", count: NewTab.maxCommandCharacters)
        let data = try ControlRequest(
            surface: "M1", command: .newTab(NewTab(command: ["claude", long]))
        ).encoded()

        #expect(throws: ControlRequest.DecodeFailure.invalidNewTab) {
            try ControlRequest.decode(data)
        }
    }

    @Test func aNamePastTheLimitIsRefusedLikeAnyOtherName() throws {
        let long = String(repeating: "n", count: ControlWire.maxNameCharacters + 1)
        let data = try ControlRequest(
            surface: "M1", command: .newTab(NewTab(name: long))
        ).encoded()

        #expect(throws: ControlRequest.DecodeFailure.nameTooLong) {
            try ControlRequest.decode(data)
        }
    }

    // MARK: - Directory resolution

    @Test func aRelativeDirectoryResolvesAgainstTheCallersWorkingDirectory() {
        let resolved = NewTab(directory: "work/montty")
            .resolvingDirectory(cwd: "/Users/dev", home: "/Users/dev")

        #expect(resolved.directory == "/Users/dev/work/montty")
    }

    @Test func dotAndDotDotAreResolved() {
        #expect(NewTab(directory: ".").resolvingDirectory(cwd: "/a/b", home: "/h").directory == "/a/b")
        #expect(NewTab(directory: "../c").resolvingDirectory(cwd: "/a/b", home: "/h").directory == "/a/c")
    }

    @Test func aLeadingTildeIsTheHomeDirectory() {
        #expect(NewTab(directory: "~").resolvingDirectory(cwd: "/a", home: "/h").directory == "/h")
        #expect(NewTab(directory: "~/code").resolvingDirectory(cwd: "/a", home: "/h").directory == "/h/code")
    }

    @Test func anAbsoluteDirectoryIsLeftAlone() {
        #expect(NewTab(directory: "/opt/x").resolvingDirectory(cwd: "/a", home: "/h").directory == "/opt/x")
    }

    @Test func noDirectoryStaysNone() {
        #expect(NewTab().resolvingDirectory(cwd: "/a", home: "/h").directory == nil)
    }
}
